double clamp(double value, double min, double max) {
  if (min > max) return value;
  return value.clamp(min, max);
}
