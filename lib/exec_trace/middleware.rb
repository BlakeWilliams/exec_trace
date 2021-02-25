# frozen_string_literal: true

module ExecTrace
  class Middleware
    def initialize(app, allowed_cb = ->(env) { true })
      @app = app
      @allowed_cb = allowed_cb
    end

    def call(env)
      request = Rack::Request.new(env)

      if request.params.has_key?("exec_trace") && @allowed_cb.call(env)
        status = headers = body = nil

        @file_cache = {}
        trace = exec_trace do
          status, headers, body = @app.call(env)
        end

        return [status, headers, body] unless headers["Content-Type"] =~ /text\/html/
        body.close if body.respond_to?(:close)

        response = Rack::Response.new(body, status, headers)
        response.write template(trace)
        response.finish
      else
        @app.call(env)
      end
    ensure
      @file_cache = {}
    end

    private

    def template(trace)
      <<~TEMPLATE
      <style>
        .exec_trace_line {
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .exec_trace_line > .exec_trace_line {
        }

        .exec_trace_line {
          border-left-width: 1px;
          border-left-color: black;
          border-left-style: solid;
        }

        .exec_trace_details.exec_trace_no_subframes summary::-webkit-details-marker {
          visibility: hidden;
        }
      </style>
      <div>
        #{trace.map { |frame| template_for(frame) }.join("")}
      </div>
      TEMPLATE
    end

    def template_for(frame, depth = 0)
      calls = frame[1]
      time_in_ms = frame[2] / 1000 # turn us into ms
      subframes = frame[3]

      <<~MARKUP
      <details class="exec_trace_details #{'exec_trace_no_subframes' if subframes.length == 0}">
        <summary class="exec_trace_line" style="margin-left: #{depth * 2}em;">
          <code style="display: inline-block; flex: 1;">#{name_for_frame(frame)}</code>
          <span style="padding: 8px">#{calls} calls</span>
          <span style="padding: 8px">#{time_in_ms}ms</span>
        </summary>

        #{subframes.map { |frame| template_for(frame, depth + 1) }.join("")}
      </details>
      MARKUP
    end

    def name_for_frame(frame)
      file_path, line_number = frame[0].split(":")
      @file_cache[file_path] ||= File.read(file_path).split("\n")
      @file_cache[file_path][line_number.to_i - 1]
    rescue StandardError => e
      puts "#{file_path}: #{e}"
      puts "returning #{frame[0]}"
      return frame[0]
    end
  end
end
