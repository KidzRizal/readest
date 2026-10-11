import { describe, it, expect, vi, afterEach } from 'vitest';
import { jwtDecode } from 'jwt-decode';
import {
  getForcedPlan,
  getStoragePlanData,
  getSubscriptionPlan,
  getTranslationPlanData,
  getUserProfilePlan,
} from '@/utils/access';

vi.mock('jwt-decode', () => ({ jwtDecode: vi.fn() }));

const mockToken = (claims: Record<string, unknown>) => {
  (jwtDecode as unknown as ReturnType<typeof vi.fn>).mockReturnValue(claims);
  return 'token';
};

describe('forced plan override (NEXT_PUBLIC_FORCED_PLAN)', () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('is off by default, so the token claim decides', () => {
    vi.stubEnv('NEXT_PUBLIC_FORCED_PLAN', '');
    vi.stubEnv('FORCED_PLAN', '');
    expect(getForcedPlan()).toBeNull();
    expect(getUserProfilePlan(mockToken({}))).toBe('free');
    expect(getSubscriptionPlan(mockToken({ plan: 'plus' }))).toBe('plus');
  });

  it('reads a token without a plan claim as the forced plan', () => {
    vi.stubEnv('NEXT_PUBLIC_FORCED_PLAN', 'pro');
    expect(getUserProfilePlan(mockToken({}))).toBe('pro');
    expect(getSubscriptionPlan(mockToken({ plan: 'free' }))).toBe('pro');
    expect(getStoragePlanData(mockToken({})).plan).toBe('pro');
    expect(getTranslationPlanData(mockToken({})).plan).toBe('pro');
  });

  it('ignores an unknown plan name instead of trusting arbitrary input', () => {
    vi.stubEnv('NEXT_PUBLIC_FORCED_PLAN', 'enterprise');
    expect(getForcedPlan()).toBeNull();
    expect(getUserProfilePlan(mockToken({ plan: 'plus' }))).toBe('plus');
  });

  it('lets the server-side FORCED_PLAN win over the public one', () => {
    vi.stubEnv('FORCED_PLAN', 'plus');
    vi.stubEnv('NEXT_PUBLIC_FORCED_PLAN', 'pro');
    expect(getForcedPlan()).toBe('plus');
  });
});
