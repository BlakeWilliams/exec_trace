# frozen_string_literal: true

require "test_helper"

class ExecTraceTest < Minitest::Test
  def test_it_does_something_useful
    result = exec_trace do
      struct = Struct.new(:x) do
        def echo
          x
        end
      end

      value = struct.new(1)
      value.echo
    end

    assert_equal 4, result.size

    assert_equal 1, result[0][1], "first trace not called once"
    assert result[0][2] > 5, "first trace microseconds is less than 5"

    last_trace = result[3]
    assert last_trace[0].end_with?("rb:15"), "expected trace to end in line 10"
    assert last_trace[3][0][0].end_with?("rb:10"), "expected first call of last trace to end in 11"
  end
end
