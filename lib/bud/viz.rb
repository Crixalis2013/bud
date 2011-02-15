require 'rubygems'
require 'syntax/convertors/html'
require 'gchart'
require 'digest/md5'
require 'bud/state'

class VizOnline
  include BudState
  def initialize(bud_instance)
    @bud_instance = bud_instance
    @meta_tables = {'t_rules' => 1, 't_depends' => 1, 't_table_info' => 1, 't_cycle' => 1, 't_stratum' => 1, 't_depends_tc' => 1, 't_table_schema' => 1}
    @bud_instance.options[:tc_dir] = "#{@bud_instance.class}_#{bud_instance.object_id}_#{bud_instance.port}"
    @table_info = new_tab(:t_table_info, [:tab_name, :tab_type], @bud_instance)
    @table_schema = new_tab(:t_table_schema, [:tab_name, :col_name, :ord], @bud_instance)

    @logtab = {}
    @bud_instance.tables.each do |t|
      next if t[0].to_s =~ /_log\z/
      news = [:bud_time]
      @table_schema << [t[0], :bud_time, 0]
      t[1].schema.each_with_index do |s, i| 
        news << s 
        @table_schema << [t[0], s, i+1]
      end
      
      lt = "#{t[0]}_log".to_sym
      @logtab[t[0]] = new_tab(lt, news, @bud_instance)
      @table_info << [t[0], t[1].class.to_s]
    end 
  end

  def new_tab(name, schema, instance)
      ret = Bud::BudTcTable.new(name, schema, instance)
      instance.tables[name] = ret
      return ret
  end

  def do_cards
    @bud_instance.tables.each do |t|
      tab = t[0]
      next if tab.to_s =~ /_log\z/
      next if @meta_tables[tab.to_s] and @bud_instance.budtime > 0
      t[1].each do |row|
        puts "initially row is #{row.inspect}"  
        nr = []
        row.each {|r| puts "\tROW ITEM: #{r.inspect}, #{r.class}"; nr << r.nil? ? "foo" : r } 
        newrow = nr.clone.unshift(@bud_instance.budtime)
        
        puts "NEWROW(#{t[0]}) is #{newrow.inspect}"
        @logtab[tab] << newrow
      end
      @logtab[tab].tick
    end
  end
end
