# frozen_string_literal: true

module ExecTrace
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status = headers = body = nil

      trace = exec_trace do
        status, headers, body = @app.call(env)
      end

      return [status, headers, body] unless headers["Content-Type"] =~ /text\/html/
      body.close if body.respond_to?(:close)

      response = Rack::Response.new(body, status, headers)
      response.write template(trace)
      response.finish
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
          <strong style="display: inline-block; flex: 1;">#{name_for_frame(frame)}</strong>
          <span style="padding: 8px">#{calls} calls</span>
          <span style="padding: 8px">#{time_in_ms}ms</span>
        </summary>

        #{subframes.map { |frame| template_for(frame, depth + 1) }.join("")}
      </details>
      MARKUP
    end

    def name_for_frame(frame)
      file_path, line_number = frame[0].split(":")
      File.read(file_path).split("\n")[line_number.to_i - 1]
    rescue StandardError => e
      puts "#{file_path}: #{e}"
      puts "returning #{frame[0]}"
      return frame[0]
    end
  end
end
