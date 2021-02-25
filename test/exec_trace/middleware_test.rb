# frozen_string_literal: true

require "test_helper"
require "rack"
require "exec_trace/middleware"

class ExecTraceMiddlewareTest < Minitest::Test
  def setup
    @app = ->(env) { [200, { "Content-Type" => "text/html" }, "<html></html>"] }
  end

  def test_middleware_runs_trace_if_param_is_set
    env = Rack::MockRequest.env_for("http://localhost:3000/?exec_trace")

    _status, _headers, body = ExecTrace::Middleware.new(@app).call(env)

    assert_includes body.last, "exec_trace_details"
  end

  def test_middleware_does_not_run_if_param_is_missing
    env = Rack::MockRequest.env_for("http://localhost:3000/")

    _status, _headers, body = ExecTrace::Middleware.new(@app).call(env)

    refute_includes body, "exec_trace_details"
  end

  def test_middleware_does_not_run_if_allowed_cb_returns_false
    env = Rack::MockRequest.env_for("http://localhost:3000/?exec_trace")

    cb = ->(env) { false }
    _status, _headers, body = ExecTrace::Middleware.new(@app, allowed_cb: cb).call(env)

    refute_includes body, "exec_trace_details"
  end
end
