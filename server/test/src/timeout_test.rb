require_relative 'test_base'

class TimeoutTest < TestBase

  def self.hex_prefix
    '45B57'
  end

  def hex_setup
    kata_setup
  end

  def hex_teardown
    kata_teardown
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test 'B2B',
  %w( [Alpine]
      when run(test-code)
        does not complete in max_seconds
          and
        does not produce output
      then
        the output is empty
          and
        the colour is timed_out
  ) do
    files['hiker.c'] = [
      '#include "hiker.h"',
      'int answer(void)',
      '{',
      '    for(;;); ',
      '    return 6 * 7;',
      '}'
    ].join("\n")
    named_args = {
      changed_files:files,
        max_seconds:2
    }
    assert_run_times_out(named_args)
    assert_equal '', stdout
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - -

  test '4D7',
  %w( [Alpine]
      when run(test-code)
        does not complete in max_seconds
          and
        does produce output
      then
        the output is not empty
          and
        the colour is timed_out
    ) do
    files['hiker.c'] = [
      '#include "hiker.h"',
      '#include <stdio.h>',
      'int answer(void)',
      '{',
      '    for(;;)',
      '        puts("Hello");',
      '    return 6 * 7;',
      '}'
    ].join("\n")
    named_args = {
      changed_files:files,
        max_seconds:2
    }
    assert_run_times_out(named_args)
    refute_equal '', stdout
  end

end


