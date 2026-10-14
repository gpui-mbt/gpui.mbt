/* Shared validated scene preflight, grayscale text, GLES2 drawing and readback.
 * Including platform supplies struct host, window_check, pump, submit_frame,
 * native_e2e_enabled, and GPUI_RENDER_EXPORT(name). submit_frame owns scheduling
 * and native swap; this file must not call Wayland or Xlib. */
struct staged_text {
  int item_index;
  struct gpui_linux_text_mask mask;
  GLuint texture;
  double u0, v0, u1, v1;
};

static void release_staged_text(struct staged_text *texts, int count,
                                 int textures_current) {
  for (int i = 0; i < count; ++i) {
    if (textures_current && texts[i].texture)
      glDeleteTextures(1, &texts[i].texture);
    gpui_linux_text_mask_release_v1(&texts[i].mask);
  }
}

static int text_status(int status) {
  switch (status) {
  case GPUI_LINUX_TEXT_OK:
    return GPUI_OK;
  case GPUI_LINUX_TEXT_UNSUPPORTED_INPUT:
  case GPUI_LINUX_TEXT_UNSUPPORTED_COLOR:
  case GPUI_LINUX_TEXT_UNSUPPORTED_RASTER:
    return GPUI_UNSUPPORTED;
  case GPUI_LINUX_TEXT_INPUT_TOO_LARGE:
  case GPUI_LINUX_TEXT_RESOURCE_LIMIT:
  case GPUI_LINUX_TEXT_CAPACITY_TOO_SMALL:
    return GPUI_RESOURCE;
  case GPUI_LINUX_TEXT_INVALID_ARGUMENT:
  case GPUI_LINUX_TEXT_INVALID_COORDINATES:
    return GPUI_INVALID;
  default:
    return GPUI_NATIVE;
  }
}

/* Validate all common fields and every transformed corner before rasterizing
 * or touching GL. Same limits as the original private quad ABI. */
static int valid_common_item(const double *q) {
  if (q[2] < 0 || q[3] < 0 || q[14] < 0 || q[14] > 1 || q[17] < 0 ||
      q[18] < 0)
    return 0;
  for (int c = 4; c < 8; ++c)
    if (q[c] < 0 || q[c] > 255)
      return 0;
  for (int j = 0; j < 4; ++j) {
    double px = q[0] + ((j == 1 || j == 3) ? q[2] : 0);
    double py = q[1] + ((j >= 2) ? q[3] : 0);
    double tx = q[8] * px + q[10] * py + q[12];
    double ty = q[9] * px + q[11] * py + q[13];
    if (!isfinite(tx) || !isfinite(ty) || fabs(tx) > 1e20 || fabs(ty) > 1e20)
      return 0;
  }
  return 1;
}

static int item_scissor(struct host *h, const double *q) {
  double left = fmax(0, q[15]), top = fmax(0, q[16]);
  double right = fmin(h->width, q[15] + q[17]);
  double bottom = fmin(h->height, q[16] + q[18]);
  if (right <= left || bottom <= top)
    return 0;
  /* Device sample centers inside the logical half-open viewport-space clip. */
  int x = (int)ceil(left * h->scale - 0.5);
  int y = (int)ceil(top * h->scale - 0.5);
  int r = (int)ceil(right * h->scale - 0.5);
  int b = (int)ceil(bottom * h->scale - 0.5);
  int dw = h->width * h->scale, dh = h->height * h->scale;
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (r < 0) r = 0;
  if (b < 0) b = 0;
  if (x > dw) x = dw;
  if (r > dw) r = dw;
  if (y > dh) y = dh;
  if (b > dh) b = dh;
  if (r <= x || b <= y)
    return 0;
  glScissor(x, dh - b, r - x, b - y);
  return 1;
}

static int32_t present_mixed(int32_t abi, int32_t expected_abi, int stride,
                            int origin_enabled, int32_t token, int32_t window,
                            const double *data, int32_t length,
                            const uint8_t *text, int32_t text_length) {
  struct host *h;
  int s = window_check(token, window, &h);
  if (s)
    return s;
  if (h->state)
    return GPUI_STOPPING;
  if (h->error)
    return h->error;
  s = pump(h, 0);
  if (s)
    return s;
  /* Native dispatch can close/destroy the target. Revalidate after callbacks
   * before staging or touching EGL; no captured host state is assumed live. */
  if (h->state)
    return GPUI_STOPPING;
  if (h->window != window || !h->configured)
    return GPUI_STALE;
  if (abi != expected_abi || !data || length < 5 ||
      (length - 5) % stride || text_length < 0 ||
      (text_length && !text))
    return GPUI_INVALID;
  if ((length - 5) / stride > GPUI_MAX_ITEMS ||
      text_length > GPUI_MAX_FRAME_TEXT_BYTES)
    return GPUI_RESOURCE;
  for (int i = 0; i < length; ++i)
    if (!isfinite(data[i]) || fabs(data[i]) > 1e20)
      return GPUI_INVALID;
  int text_count = 0;
  for (int i = 5; i < length; i += stride) {
    const double *record = data + i, *q = record + 1;
    if (record[0] != 0 && record[0] != 1 &&
        (!origin_enabled || record[0] != 2))
      return GPUI_UNSUPPORTED;
    if (origin_enabled && record[0] != 2 &&
        (record[23] != 0 || record[24] != 0))
      return GPUI_INVALID;
    if (!valid_common_item(q))
      return GPUI_INVALID;
    if (record[0] == 0) {
      if (record[20] != 0 || record[21] != 0 || record[22] != 0)
        return GPUI_INVALID;
    } else {
      if (++text_count > GPUI_MAX_TEXT_ITEMS)
        return GPUI_RESOURCE;
      if (record[20] < 0 || record[21] < 0 ||
          record[20] > text_length || record[21] > text_length - record[20] ||
          floor(record[20]) != record[20] || floor(record[21]) != record[21] ||
          record[22] <= 0)
        return GPUI_INVALID;
      if (record[21] > GPUI_LINUX_TEXT_MAX_TEXT_BYTES)
        return GPUI_RESOURCE;
      if (record[22] > GPUI_LINUX_TEXT_MAX_FONT_SIZE_PX)
        return GPUI_UNSUPPORTED;
    }
  }
  if (data[0] != 0 || data[1] != 0)
    return GPUI_UNSUPPORTED;
  if (data[2] != h->width || data[3] != h->height || data[4] != h->scale)
    return GPUI_BUSY;
  if (!h->configured || h->frame)
    return GPUI_BUSY;

  struct staged_text texts[GPUI_MAX_TEXT_ITEMS] = {0};
  int staged = 0;
  size_t total_mask_bytes = 0;
  static const uint8_t sans[] = "sans";
  for (int i = 5; i < length; i += stride) {
    const double *record = data + i, *q = record + 1;
    if (record[0] == 0)
      continue;
    struct staged_text *item = texts + staged;
    item->item_index = (i - 5) / stride;
    ++staged;
    int offset = (int)record[20], bytes = (int)record[21];
    const uint8_t *span = bytes ? text + offset : (const uint8_t *)"";
    int32_t budget = (int32_t)(GPUI_MAX_FRAME_MASK_BYTES - total_mask_bytes);
    if (record[0] == 2) {
      struct gpui_linux_text_mask_v2 mask = {0};
      s = text_status(gpui_linux_text_raster_v2(
          GPUI_LINUX_TEXT_RASTER_ABI, span, bytes, sans, 4, record[22],
          record[23], record[24], q[0], q[1], q[2], q[3], budget, &mask));
      if (!s) {
        item->mask = mask.mask; // Transfer the successful pixel ownership.
        item->u0 = mask.u0; item->v0 = mask.v0;
        item->u1 = mask.u1; item->v1 = mask.v1;
        memset(&mask, 0, sizeof(mask));
      }
    } else {
      s = text_status(gpui_linux_text_raster_v1(
          GPUI_LINUX_TEXT_ABI, span, bytes, sans, 4, record[22], q[2], q[3],
          budget, &item->mask));
      if (!s && item->mask.pixels) {
        item->u1 = (item->mask.right - item->mask.left) / item->mask.width;
        item->v1 = (item->mask.bottom - item->mask.top) / item->mask.height;
      }
    }
    if (s)
      goto preflight_failure;
    size_t mask_bytes = (size_t)item->mask.width * (size_t)item->mask.height;
    if (mask_bytes > GPUI_MAX_FRAME_MASK_BYTES - total_mask_bytes) {
      s = GPUI_RESOURCE;
      goto preflight_failure;
    }
    total_mask_bytes += mask_bytes;
  }
  if (h->egl_surface == EGL_NO_SURFACE ||
      !eglMakeCurrent(h->egl, h->egl_surface, h->egl_surface, h->context)) {
    s = GPUI_SURFACE_LOST;
    goto preflight_failure;
  }
  if (glGetError() != GL_NO_ERROR) {
    s = GPUI_DEVICE_LOST;
    goto preflight_failure;
  }
  GLint maximum_texture = 0;
  glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maximum_texture);
  if (maximum_texture <= 0 || glGetError() != GL_NO_ERROR) {
    s = GPUI_DEVICE_LOST;
    goto preflight_failure;
  }
  glActiveTexture(GL_TEXTURE0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  for (int i = 0; i < staged; ++i) {
    struct staged_text *item = texts + i;
    if (!item->mask.pixels)
      continue;
    if (item->mask.width > maximum_texture || item->mask.height > maximum_texture) {
      s = GPUI_RESOURCE;
      goto texture_failure;
    }
    glGenTextures(1, &item->texture);
    glBindTexture(GL_TEXTURE_2D, item->texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA, item->mask.width, item->mask.height,
                 0, GL_ALPHA, GL_UNSIGNED_BYTE, item->mask.pixels);
    GLenum error = glGetError();
    if (!item->texture || error != GL_NO_ERROR) {
      s = error == GL_OUT_OF_MEMORY ? GPUI_RESOURCE : GPUI_DEVICE_LOST;
      goto texture_failure;
    }
  }

  /* All inputs, Pango layouts, allocations and uploads passed before clear.
   * Device/surface failures after this point retain the existing typed recovery
   * semantics; they are not an atomic-display guarantee. */
  glViewport(0, 0, h->width * h->scale, h->height * h->scale);
  glDisable(GL_SCISSOR_TEST);
  glClearColor(0, 0, 0, 0);
  glClear(GL_COLOR_BUFFER_BIT);
  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  glEnableVertexAttribArray(0);
  glEnable(GL_SCISSOR_TEST);
  int text_index = 0;
  for (int i = 5; i < length; i += stride) {
    const double *record = data + i, *q = record + 1;
    struct staged_text *item = NULL;
    if (record[0] != 0)
      item = texts + text_index++;
    if (!item_scissor(h, q) || (item && !item->texture))
      continue;
    double left = q[0], top = q[1], right = q[0] + q[2], bottom = q[1] + q[3];
    GLfloat uvs[8];
    GLint color_uniform;
    if (item) {
      const struct gpui_linux_text_mask *mask = &item->mask;
      double offset_x = record[0] == 1 ? q[0] : 0;
      double offset_y = record[0] == 1 ? q[1] : 0;
      left = offset_x + mask->left;
      top = offset_y + mask->top;
      right = offset_x + mask->right;
      bottom = offset_y + mask->bottom;
      GLfloat mapped[8] = {
          (GLfloat)item->u0, (GLfloat)item->v0,
          (GLfloat)item->u1, (GLfloat)item->v0,
          (GLfloat)item->u0, (GLfloat)item->v1,
          (GLfloat)item->u1, (GLfloat)item->v1};
      memcpy(uvs, mapped, sizeof(uvs));
      glUseProgram(h->mask_program);
      glUniform1i(h->mask_sampler_uniform, 0);
      glBindTexture(GL_TEXTURE_2D, item->texture);
      glEnableVertexAttribArray(1);
      glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, uvs);
      color_uniform = h->mask_color_uniform;
    } else {
      glUseProgram(h->program);
      glDisableVertexAttribArray(1);
      color_uniform = h->color_uniform;
    }
    GLfloat vertices[8];
    for (int j = 0; j < 4; ++j) {
      double px = (j == 1 || j == 3) ? right : left;
      double py = j >= 2 ? bottom : top;
      double tx = q[8] * px + q[10] * py + q[12];
      double ty = q[9] * px + q[11] * py + q[13];
      vertices[j * 2] = (GLfloat)(2 * tx / h->width - 1);
      vertices[j * 2 + 1] = (GLfloat)(1 - 2 * ty / h->height);
    }
    float alpha = (float)(q[7] / 255.0 * q[14]);
    glUniform4f(color_uniform, (float)(q[4] / 255.0) * alpha,
                (float)(q[5] / 255.0) * alpha, (float)(q[6] / 255.0) * alpha,
                alpha);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, vertices);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  }
  glDisableVertexAttribArray(0);
  glDisableVertexAttribArray(1);
  glDisable(GL_SCISSOR_TEST);
  glBindTexture(GL_TEXTURE_2D, 0);
  release_staged_text(texts, staged, 1);
  if (glGetError() != GL_NO_ERROR)
    return GPUI_DEVICE_LOST;
  uint8_t *captured = NULL;
  int capture_width = 0;
  int capture_height = 0;
  int64_t capture_width64 = (int64_t)h->width * h->scale;
  int64_t capture_height64 = (int64_t)h->height * h->scale;
  if (native_e2e_enabled()) {
    int64_t capture_pixels = capture_width64 * capture_height64;
    if (capture_width64 <= 0 || capture_height64 <= 0 ||
        capture_width64 > 16384 || capture_height64 > 16384 ||
        capture_pixels > 16 * 1024 * 1024)
      return GPUI_RESOURCE;
    capture_width = (int)capture_width64;
    capture_height = (int)capture_height64;
    size_t capture_bytes = (size_t)capture_pixels * 4;
    captured = malloc(capture_bytes);
    uint8_t *row = malloc((size_t)capture_width * 4);
    if (!captured || !row) {
      free(captured);
      free(row);
      return GPUI_RESOURCE;
    }
    GLint old_pack_alignment = 4;
    glGetIntegerv(GL_PACK_ALIGNMENT, &old_pack_alignment);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glFinish();
    glReadPixels(0, 0, capture_width, capture_height, GL_RGBA,
                 GL_UNSIGNED_BYTE, captured);
    GLenum capture_error = glGetError();
    glPixelStorei(GL_PACK_ALIGNMENT, old_pack_alignment);
    if (capture_error != GL_NO_ERROR || glGetError() != GL_NO_ERROR) {
      free(captured);
      free(row);
      return GPUI_DEVICE_LOST;
    }
    for (int y = 0; y < capture_height / 2; ++y) {
      uint8_t *top = captured + (size_t)y * (size_t)capture_width * 4;
      uint8_t *bottom = captured + (size_t)(capture_height - y - 1) *
                                       (size_t)capture_width * 4;
      memcpy(row, top, (size_t)capture_width * 4);
      memcpy(top, bottom, (size_t)capture_width * 4);
      memcpy(bottom, row, (size_t)capture_width * 4);
    }
    free(row);
  }
  s = submit_frame(h);
  if (s) {
    free(captured);
    return s;
  }
  if (captured) {
    free(h->frame_pixels);
    h->frame_pixels = captured;
    h->frame_width = capture_width;
    h->frame_height = capture_height;
    h->frame_scale = h->scale;
  }
  return GPUI_OK;

texture_failure:
  glBindTexture(GL_TEXTURE_2D, 0);
  release_staged_text(texts, staged, 1);
  return s;
preflight_failure:
  release_staged_text(texts, staged, 0);
  return s;
}

int32_t GPUI_RENDER_EXPORT(present_v2)(int32_t abi, int32_t token, int32_t window,
                        const double *data, int32_t length,
                        const uint8_t *text, int32_t text_length) {
  return present_mixed(abi, GPUI_MIXED_FRAME_ABI, GPUI_MIXED_STRIDE, 0,
      token, window, data, length, text, text_length);
}
int32_t GPUI_RENDER_EXPORT(present_v3)(int32_t abi, int32_t token, int32_t window,
                        const double *data, int32_t length,
                        const uint8_t *text, int32_t text_length) {
  return present_mixed(abi, GPUI_ORIGIN_FRAME_ABI, GPUI_ORIGIN_STRIDE, 1,
      token, window, data, length, text, text_length);
}

int32_t GPUI_RENDER_EXPORT(test_frame_metrics_v1)(int32_t token, int32_t window,
                                   double *output) {
  struct host *h;
  int status = window_check(token, window, &h);
  if (status)
    return status;
  if (!native_e2e_enabled())
    return GPUI_UNSUPPORTED;
  if (!output)
    return GPUI_INVALID;
  if (!h->frame_pixels || h->frame_width <= 0 || h->frame_height <= 0)
    return GPUI_BUSY;
  output[0] = h->frame_width;
  output[1] = h->frame_height;
  output[2] = h->frame_scale;
  return GPUI_OK;
}

int32_t GPUI_RENDER_EXPORT(test_frame_copy_v1)(int32_t token, int32_t window,
                                uint8_t *output, int32_t capacity) {
  struct host *h;
  int status = window_check(token, window, &h);
  if (status)
    return status;
  if (!native_e2e_enabled())
    return GPUI_UNSUPPORTED;
  if (!h->frame_pixels || h->frame_width <= 0 || h->frame_height <= 0)
    return GPUI_BUSY;
  int64_t required = (int64_t)h->frame_width * h->frame_height * 4;
  if (required > 64 * 1024 * 1024)
    return GPUI_RESOURCE;
  if (!output || capacity < 0 || capacity != required)
    return GPUI_INVALID;
  memcpy(output, h->frame_pixels, (size_t)required);
  return GPUI_OK;
}

int32_t GPUI_RENDER_EXPORT(present)(int32_t token, int32_t window, const double *data,
                     int32_t length) {
  if (!data || length < 5 || (length - 5) % GPUI_QUAD_STRIDE)
    return GPUI_INVALID;
  int count = (length - 5) / GPUI_QUAD_STRIDE;
  if (count > GPUI_MAX_ITEMS)
    return GPUI_RESOURCE;
  int mixed_length = 5 + count * GPUI_MIXED_STRIDE;
  double *mixed = malloc((size_t)mixed_length * sizeof(double));
  if (!mixed)
    return GPUI_RESOURCE;
  memcpy(mixed, data, 5 * sizeof(double));
  for (int i = 0; i < count; ++i) {
    double *record = mixed + 5 + i * GPUI_MIXED_STRIDE;
    record[0] = 0;
    memcpy(record + 1, data + 5 + i * GPUI_QUAD_STRIDE,
            GPUI_QUAD_STRIDE * sizeof(double));
    record[20] = record[21] = record[22] = 0;
  }
  int status = GPUI_RENDER_EXPORT(present_v2)(GPUI_MIXED_FRAME_ABI, token, window, mixed,
                               mixed_length, NULL, 0);
  free(mixed);
  return status;
}
