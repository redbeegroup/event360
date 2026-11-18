import { normalizeMyanmarPhone } from './phone';

describe('normalizeMyanmarPhone', () => {
  it.each([
    ['09123456789', '+959123456789'],
    ['09 123 456 789', '+959123456789'],
    ['959123456789', '+959123456789'],
    ['+959-1234-5678', '+95912345678'],
  ])('%s → %s', (input, expected) => {
    expect(normalizeMyanmarPhone(input)).toBe(expected);
  });

  it.each(['12345', '+6591234567', '09123', 'abc', '0912345678901'])('rejects %s', (input) => {
    expect(normalizeMyanmarPhone(input)).toBeNull();
  });
});
