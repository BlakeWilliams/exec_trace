#include <ruby.h>
#include <stdio.h>

#include <sys/time.h>
#include <time.h>

#include <ruby/debug.h>
#include <ruby/intern.h>

typedef uint64_t usec_t;

static usec_t
wall_usec()
{
  struct timeval tv;
  gettimeofday(&tv, NULL);

  // Convert timestamp to us
  return (usec_t)tv.tv_sec * 1000000 + (usec_t)tv.tv_usec;
}

typedef struct frame
{
  rb_event_flag_t event;
  char* file_name;
  int line_number;
  int calls;

  struct frame* parent;

  int subframe_count;
  int subframe_size;
  struct frame** subframes;

  usec_t wall_total_usec;
  usec_t wall_start_usec;
  usec_t wall_children_usec;
} frame_t;

static struct
{
  uint64_t top_frame_used;
  frame_t* top_frames[65536];
  frame_t* last_frame;
  VALUE thread;
} tracer = {};

static void
trace_hook(rb_event_flag_t event, VALUE data, VALUE self, ID mid, VALUE klass)
{
  // Ignore other threads
  if (tracer.thread != rb_thread_current()) {
    return;
  }

  int buff_size = 2;
  VALUE buff[buff_size];
  int lines[buff_size];
  // https://github.com/ruby/ruby/blob/48b94b791997881929c739c64f95ac30f3fd0bb9/include/ruby/debug.h
  // start 0, limit to 2 frames, buff = iseqs, lines == line numbers
  int collected_size = rb_profile_frames(0, buff_size, buff, lines);

  if (collected_size == 0) {
    return;
  }

  int line_index = 0;

  if (!mid && collected_size == 2) {
    line_index = 1;
  }

  VALUE path = rb_profile_frame_absolute_path(buff[line_index]);

  if (NIL_P(path)) {
    line_index = 0;
    path = rb_profile_frame_absolute_path(buff[line_index]);
    if (NIL_P(path)) {
      return;
    }
  }
  char* file = StringValueCStr(path);
  int line = lines[line_index];

  if (!file || line <= 0) {
    return;
  }

  frame_t* frame;
  frame_t* last_top_frame = tracer.top_frames[tracer.top_frame_used - 1];

  switch (event) {
    case RUBY_EVENT_CALL:
    case RUBY_EVENT_C_CALL:
      if (tracer.last_frame && tracer.last_frame->file_name == file &&
          tracer.last_frame->line_number == line) {
        // collapse duplicate frames
        return;
      } else if (last_top_frame && last_top_frame->file_name == file &&
                 last_top_frame->line_number == line) {
        // collapse duplicate top-level frames
        return;
      } else {
        if (tracer.last_frame) {
          for (int i = 0; i < tracer.last_frame->subframe_count; i++) {
            frame = tracer.last_frame->subframes[i];

            if (frame->file_name == file && frame->line_number == line) {
              frame->calls++;
              frame->wall_start_usec = wall_usec();
              tracer.last_frame = frame;
              return;
            }
          }
        }

        frame = malloc(sizeof(frame_t));

        frame->event = event;
        frame->file_name = file;
        frame->line_number = line;
        frame->calls = 1;
        frame->subframe_count = 0;
        frame->subframe_size = 1;
        frame->subframes = malloc(1 * sizeof(frame_t*));
        frame->wall_start_usec = wall_usec();
        frame->wall_total_usec = 0;
        frame->wall_children_usec = 0;
        frame->parent = tracer.last_frame;

        if (tracer.last_frame) {
          frame_t* last_frame = tracer.last_frame;
          if (last_frame->subframe_size == last_frame->subframe_count) {
            last_frame->subframe_size *= 2;
            tracer.last_frame->subframes =
              realloc(tracer.last_frame->subframes,
                      sizeof(frame_t*) * last_frame->subframe_size);
          }

          last_frame->subframe_count++;
          last_frame->subframes[last_frame->subframe_count - 1] = frame;
        } else {
          tracer.top_frame_used++;
          tracer.top_frames[tracer.top_frame_used - 1] = frame;
        }
      }

      tracer.last_frame = frame;
      break;
    case RUBY_EVENT_RETURN:
    case RUBY_EVENT_C_RETURN: {
      frame_t* current_frame = tracer.last_frame;
      while (1) {
        if (current_frame && current_frame->file_name == file &&
            current_frame->line_number == line) {
          usec_t time = wall_usec() - tracer.last_frame->wall_start_usec;
          if (tracer.last_frame->parent) {
            tracer.last_frame->parent->wall_children_usec += time;
          }
          tracer.last_frame->wall_total_usec += time;
          tracer.last_frame = current_frame->parent;
          return;
        } else if (current_frame) {
          current_frame = current_frame->parent;
        } else {
          return;
        }
      }
    }
  }
}

/*
  Ensure trace is cleaned up by removing the event hook.
*/
static VALUE
exec_trace_ensure(VALUE self)
{
  rb_remove_event_hook((rb_event_hook_func_t)trace_hook);

  return self;
}

static void
create_frame_array(VALUE arr, frame_t* frame)
{
  VALUE fname = rb_sprintf("%s:%i", frame->file_name, frame->line_number);
  rb_ary_push(arr, fname);
  rb_ary_push(arr, INT2FIX(frame->calls));
  rb_ary_push(arr, INT2FIX(frame->wall_total_usec - frame->wall_children_usec));

  VALUE subframe_ary = rb_ary_new();

  if (frame->subframe_count == 0) {
    rb_ary_push(arr, subframe_ary);
    return;
  }

  for (int i = 0; i < frame->subframe_count; i++) {
    VALUE frame_ary = rb_ary_new();
    create_frame_array(frame_ary, frame->subframes[i]);
    rb_ary_push(subframe_ary, frame_ary);
  }

  rb_ary_push(arr, subframe_ary);
}

static void
cleanup(frame_t* frame)
{
  if (frame->subframe_count > 0) {
    for (int i = 0; i < frame->subframe_count; i++) {
      cleanup(frame->subframes[i]);
    }
  }

  free(frame->subframes);
  free(frame);
}

/*
  Global function that begins tracing
*/
VALUE
exec_trace(VALUE self)
{
  // Capture current thread ID to ensure we don't capture frames from other
  // threads.
  tracer.thread = rb_thread_current();

  // Start listening for call events
  rb_add_event_hook((rb_event_hook_func_t)trace_hook,
                    RUBY_EVENT_CALL | RUBY_EVENT_C_CALL | RUBY_EVENT_RETURN |
                      RUBY_EVENT_C_RETURN,
                    Qnil);

  // Call passed in block, ensure trace hook is removed
  rb_ensure(rb_yield, Qnil, exec_trace_ensure, self);

  VALUE top_level_frame_ary = rb_ary_new();

  for (uint64_t i = 0; i < tracer.top_frame_used; i++) {
    VALUE frame_ary = rb_ary_new();
    create_frame_array(frame_ary, tracer.top_frames[i]);
    rb_ary_push(top_level_frame_ary, frame_ary);

    // Cleanup malloc'd memory
    cleanup(tracer.top_frames[i]);
  }

  // Cleanup for another run
  tracer.top_frame_used = 0;
  tracer.last_frame = NULL;
  memset(tracer.top_frames, 0, sizeof(tracer.top_frames));

  return top_level_frame_ary;
}

/*
   Entrypoint for a gem extension and defines the global
   `exec_trace` function.
*/
void
Init_exec_trace(void)
{
  rb_define_global_function("exec_trace", exec_trace, 0);
  rb_define_module("ExecTrace");
}
