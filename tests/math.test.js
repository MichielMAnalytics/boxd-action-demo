// tests/math.test.js
import { describe, it, expect } from 'vitest';
import { sum } from '../app/math.js';

describe('sum', () => {
  it('sums a list of numbers', () => {
    expect(sum([1, 2, 3])).toBe(6);
  });
});
