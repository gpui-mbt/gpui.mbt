/* Private shared GLES2 shader setup. The including platform owns EGL and
 * supplies struct host with renderer fields. No platform connection operations. */
static GLuint shader(GLenum type, const char *src) {
  GLuint sh = glCreateShader(type);
  glShaderSource(sh, 1, &src, NULL);
  glCompileShader(sh);
  GLint ok;
  glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    glDeleteShader(sh);
    return 0;
  }
  return sh;
}
static int create_programs(struct host *h) {
  if (!h->program) {
    GLuint v =
        shader(GL_VERTEX_SHADER,
               "attribute vec2 pos; void main(){gl_Position=vec4(pos,0.,1.);}");
    GLuint f = shader(
        GL_FRAGMENT_SHADER,
        "precision mediump float; uniform vec4 color; "
        "void main(){gl_FragColor=color;}");
    if (!v || !f) {
      if (v)
        glDeleteShader(v);
      if (f)
        glDeleteShader(f);
      return GPUI_DEVICE_LOST;
    }
    h->program = glCreateProgram();
    glAttachShader(h->program, v);
    glAttachShader(h->program, f);
    glBindAttribLocation(h->program, 0, "pos");
    glLinkProgram(h->program);
    glDeleteShader(v);
    glDeleteShader(f);
    GLint ok;
    glGetProgramiv(h->program, GL_LINK_STATUS, &ok);
    if (!ok)
      return GPUI_DEVICE_LOST;
    h->color_uniform = glGetUniformLocation(h->program, "color");
  }
  if (!h->mask_program) {
    GLuint v = shader(GL_VERTEX_SHADER,
        "attribute vec2 pos; attribute vec2 uv; varying vec2 texcoord; "
        "void main(){gl_Position=vec4(pos,0.,1.);texcoord=uv;}");
    GLuint f = shader(GL_FRAGMENT_SHADER,
        "precision mediump float; uniform vec4 color; uniform sampler2D mask; "
        "varying vec2 texcoord; "
        "void main(){gl_FragColor=color*texture2D(mask,texcoord).a;}");
    if (!v || !f) {
      if (v) glDeleteShader(v);
      if (f) glDeleteShader(f);
      return GPUI_DEVICE_LOST;
    }
    h->mask_program = glCreateProgram();
    glAttachShader(h->mask_program, v);
    glAttachShader(h->mask_program, f);
    glBindAttribLocation(h->mask_program, 0, "pos");
    glBindAttribLocation(h->mask_program, 1, "uv");
    glLinkProgram(h->mask_program);
    glDeleteShader(v);
    glDeleteShader(f);
    GLint ok;
    glGetProgramiv(h->mask_program, GL_LINK_STATUS, &ok);
    if (!ok) return GPUI_DEVICE_LOST;
    h->mask_color_uniform = glGetUniformLocation(h->mask_program, "color");
    h->mask_sampler_uniform = glGetUniformLocation(h->mask_program, "mask");
  }
  return GPUI_OK;
}
