// app/math.js
export function sum(numbers) {
  // BUG: does not handle empty array; should return 0.
  return numbers.reduce((a, b) => a + b);
}

export function average(numbers) {
  return sum(numbers) / numbers.length;
}
