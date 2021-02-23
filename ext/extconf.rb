require 'mkmf'

have_header "ruby/intern.h"
have_header "ruby/debug.h"
have_func('rb_profile_frames')
have_func('rb_thread_current')

create_makefile "exec_trace"
