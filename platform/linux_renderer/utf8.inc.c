/* Strict UTF8, independent of text-field policy. The producer omits action
 * controls as text, while the reusable field validates all committed inputs. */
static int direct_utf8_valid(const uint8_t *text, int length) {
  int i = 0;
  while (i < length) {
    uint32_t value;
    int count;
    uint8_t first = text[i];
    if (first < 0x80) {
      value = first;
      count = 1;
    } else if (first >= 0xc2 && first <= 0xdf) {
      value = first & 0x1f;
      count = 2;
    } else if (first >= 0xe0 && first <= 0xef) {
      value = first & 0x0f;
      count = 3;
    } else if (first >= 0xf0 && first <= 0xf4) {
      value = first & 0x07;
      count = 4;
    } else {
      return 0;
    }
    if (count > length - i)
      return 0;
    for (int j = 1; j < count; ++j) {
      uint8_t next = text[i + j];
      if ((next & 0xc0) != 0x80)
        return 0;
      value = (value << 6) | (next & 0x3f);
    }
    if ((count == 2 && value < 0x80) ||
        (count == 3 && value < 0x800) ||
        (count == 4 && value < 0x10000) || value > 0x10ffff ||
        (value >= 0xd800 && value <= 0xdfff))
      return 0;
    i += count;
  }
  return 1;
}
static int direct_has_control(const uint8_t *text, int length) {
  for (int i = 0; i < length; ++i) {
    if (text[i] < 0x20 || text[i] == 0x7f)
      return 1;
    if (text[i] == 0xc2 && i + 1 < length &&
        text[i + 1] >= 0x80 && text[i + 1] <= 0x9f)
      return 1;
    if (text[i] == 0xe2 && i + 2 < length && text[i + 1] == 0x80 &&
        (text[i + 2] == 0xa8 || text[i + 2] == 0xa9))
      return 1;
  }
  return 0;
}
