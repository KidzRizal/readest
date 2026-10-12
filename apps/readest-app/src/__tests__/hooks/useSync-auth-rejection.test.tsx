import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { act, cleanup, renderHook } from '@testing-library/react';
import type { SystemSettings } from '@/types/settings';

/**
 * A sync server that rejects the token ("Not authenticated") is not the same
 * as the user being signed out. Self-hosted builds can sign in against their
 * own auth project while the sync API still points at a host backed by a
 * different one; the pull then fails with 403 on every launch. Clearing
 * keepLogin and redirecting to /auth in that case made the session look lost
 * each time the app was opened. Only a missing local session signs out.
 */

const h = vi.hoisted(() => {
  const storeState = {
    settings: { version: 1, keepLogin: true } as unknown as SystemSettings,
    setSettings: vi.fn((s: SystemSettings) => {
      storeState.settings = s;
    }),
    saveSettings: vi.fn(async () => {}),
  };
  return {
    storeState,
    navigateToLogin: vi.fn(),
    getAccessToken: vi.fn<() => Promise<string | null>>(),
  };
});

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));
vi.mock('@/context/EnvContext', () => ({ useEnv: () => ({ envConfig: { id: 'env' } }) }));

const syncClientMock = vi.hoisted(() => ({
  pullChanges: vi.fn(),
  pushChanges: vi.fn(),
}));
vi.mock('@/context/SyncContext', () => ({
  useSyncContext: () => ({ syncClient: syncClientMock }),
}));
vi.mock('@/services/sync/syncCategories', () => ({ isSyncCategoryEnabled: () => true }));
vi.mock('@/store/settingsStore', () => {
  const useSettingsStore = (() => h.storeState) as unknown as {
    (): typeof h.storeState;
    getState: () => typeof h.storeState;
  };
  useSettingsStore.getState = () => h.storeState;
  return { useSettingsStore };
});
vi.mock('@/store/bookDataStore', () => ({
  useBookDataStore: () => ({ getConfig: () => null, setConfig: vi.fn() }),
}));
vi.mock('@/store/readerStore', () => ({ useReaderStore: () => ({ setIsSyncing: vi.fn() }) }));
vi.mock('@/utils/nav', () => ({ navigateToLogin: h.navigateToLogin }));
vi.mock('@/utils/access', () => ({ getAccessToken: h.getAccessToken }));
vi.mock('@/utils/transform', () => ({
  transformBookFromDB: (x: unknown) => x,
  transformBookNoteFromDB: (x: unknown) => x,
  transformBookConfigFromDB: (x: unknown) => x,
}));

import { useSync } from '@/hooks/useSync';

const pullOnce = async () => {
  const { result } = renderHook(() => useSync());
  await act(async () => {
    await result.current.pullChanges('configs', 0, vi.fn(), vi.fn());
  });
  return result;
};

beforeEach(() => {
  h.storeState.settings = { version: 1, keepLogin: true } as unknown as SystemSettings;
  h.storeState.setSettings.mockClear();
  h.navigateToLogin.mockClear();
  h.getAccessToken.mockReset();
  syncClientMock.pullChanges.mockReset();
  syncClientMock.pullChanges.mockRejectedValue(
    new Error('Failed to pull changes: Not authenticated'),
  );
});

afterEach(() => {
  cleanup();
});

describe('useSync auth rejection handling', () => {
  test('keeps the user signed in when the server rejects a still-present session', async () => {
    h.getAccessToken.mockResolvedValue('valid-local-token');

    const result = await pullOnce();

    expect(h.storeState.settings.keepLogin).toBe(true);
    expect(h.navigateToLogin).not.toHaveBeenCalled();
    // The failure is still surfaced, just without signing the user out.
    expect(result.current.syncError).toContain('Not authenticated');
  });

  test('signs out and redirects when there is no local session', async () => {
    h.getAccessToken.mockResolvedValue(null);

    await pullOnce();

    expect(h.storeState.settings.keepLogin).toBe(false);
    expect(h.navigateToLogin).toHaveBeenCalledTimes(1);
  });

  test('treats a session lookup failure as signed out', async () => {
    h.getAccessToken.mockRejectedValue(new Error('storage unavailable'));

    await pullOnce();

    expect(h.storeState.settings.keepLogin).toBe(false);
    expect(h.navigateToLogin).toHaveBeenCalledTimes(1);
  });
});
