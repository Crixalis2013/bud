require 'test_common'

require 'tc_aggs'
require 'tc_callback'
require 'tc_channel'
require 'tc_collections'
require 'tc_coverage'
require 'tc_delta'
require 'tc_errors'
# require 'tc_evaluation'
require 'tc_exists'
require 'tc_inheritance'
require 'tc_interface'
require 'tc_joins'
require 'tc_mapvariants'
require 'tc_meta'
require 'tc_module'
require 'tc_nest'
require 'tc_schemafree'
require 'tc_semistructured'
require 'tc_temp'
require 'tc_terminal'
require 'tc_timer'
require 'tc_wc1'
require 'tc_wc2'
require 'tc_rebl'

if defined? Bud::HAVE_TOKYO_CABINET
  puts "Running TC tests"
  require 'tc_tc'
else
  puts "Skipping TC tests"
end
