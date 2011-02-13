require 'rubygems'
require 'syntax/convertors/html'
require 'gchart'
require 'digest/md5'

class Viz
  def initialize(bud_instance)
    # needs:  class, object_id, options, tables, budtime
    @bud_instance = bud_instance
    @table_cards = {}
    @series_fp = File.open("series_#{bud_instance.object_id}.txt", "w")
  end

  def time_node_header
    "@ #{@bud_instance.budtime}<br>[#{@bud_instance.ip_port}]"
  end

  def prepare_viz
    return unless @bud_instance.options[:visualize]
    unless File::directory? "time_pics"
      Dir.mkdir("time_pics")
    end

    arr = [@bud_instance.class.to_s, @bud_instance.object_id.to_s]
    arr << @bud_instance.options[:tag] if @bud_instance.options[:tag]
    @time_pics_dir = "time_pics/#{arr.join("_")}"
    create_clean(@time_pics_dir)
    create_clean("plotter_out")
  end

  def visualize(strat, name, rules, depa=nil)
    # collapsed
    gv = GraphGen.new(strat.stratum, @bud_instance.tables, strat.cycle, name, @bud_instance, @time_pics_dir, true, depa)
    gv.process(strat.depends)
    gv.dump(rules)
    gv.finish

    # detail
    gv = GraphGen.new(strat.stratum, @bud_instance.tables, strat.cycle, name, @bud_instance, @time_pics_dir, false, depa)
    gv.process(strat.depends)
    gv.dump(rules)
    gv.finish
  end


  def create_clean(dir)
    if File::directory? dir
      # fix.
      `rm -r #{dir}`
    end
    Dir.mkdir(dir)
  end

  def do_cards
    return unless @bud_instance.options[:visualize]
    cards = {}
    @bud_instance.tables.each do |t|
      tab = t[0].to_s
      cards[tab] = t[1].length
      unless @table_cards[tab]
        @table_cards[tab] = {}
      end
      @table_cards[tab][@bud_instance.budtime] = t[1].length
      # or, make it URLs
      series = @table_cards[tab].sort{|a,b| a[0] <=> b[0]}.map{|v| v[1]}
      ##puts "SERIES: [#{series.join(",")}]"
      name = "#{self.object_id}_#{@bud_instance.budtime}.png"
      # PROTOTYPE.  very silly things to do on the critical path :)
      #cht = Gchart.bar(:format => 'file', :filename => name, :data => @table_cards[tab].sort{|a,b| a[0] <=> b[0]}.map{|v| v[1]})
      #cards[tab] = "#{ENV['PWD']}/#{name}"
      #puts "CHT #{cht}"
      write_timeseries(tab, series)
      write_table_contents(t) if @bud_instance.options[:visualize] >= 3
    end
    write_svgs(cards)
    write_html
  end

  def write_timeseries(tab, series)
    name = "#{tab}_#{self.object_id}_#{@bud_instance.budtime}.txt"
    @series_fp.puts "#{@bud_instance.budtime},#{tab}," + series.join(",")
    @series_fp.flush
  end
  
  def write_table_contents(tab)
    fout = File.new("#{@time_pics_dir}/#{tab[0]}_#{@bud_instance.budtime}.html", "w")
    fout.puts "<h1>#{tab[0]} #{time_node_header()}</h1>"
    fout.puts "<table border=1>"
    fout.puts "<tr>" + tab[1].schema.map{|s| "<th> #{s} </th>"}.join(" ") + "<tr>"
    tab[1].each do |row|
      fout.puts "<tr>"
      fout.puts row.map{|c| "<td>#{c.to_s}</td>"}.join(" ")

      fout.puts "</tr>"
    end
    fout.puts "</table>"
    fout.close
  end

  def write_svgs(c)
    sts = @bud_instance.meta_parser.strat_state
    return if sts.nil?
    gv = GraphGen.new(sts.stratum, @bud_instance.tables, sts.cycle, "#{@time_pics_dir}/#{@bud_instance.class}_tm_#{@bud_instance.budtime}", @bud_instance, @time_pics_dir, false, @depanalysis, c)
    gv.process(sts.depends)
    gv.finish
  end

  def write_html
    nm = "#{@bud_instance.class}_tm_#{@bud_instance.budtime}"
    prev = "#{@bud_instance.class}_tm_#{@bud_instance.budtime-1}"
    nxt = "#{@bud_instance.class}_tm_#{@bud_instance.budtime+1}"
    fout = File.new("#{@time_pics_dir}/#{nm}.html", "w")
    fout.puts "<center><h1>#{@bud_instance.class} #{time_node_header()}</h1><center>"
    fout.puts "<embed src=\"#{ENV['PWD']}/#{@time_pics_dir}/#{nm}_expanded.svg\" width=\"100%\" height=\"75%\" type=\"image/svg+xml\" pluginspage=\"http://www.adobe.com/svg/viewer/install/\" />"
    fout.puts "<hr><h2><a href=\"#{ENV['PWD']}/#{@time_pics_dir}/#{prev}.html\">prev</a>"
    fout.puts "<a href=\"#{ENV['PWD']}/#{@time_pics_dir}/#{nxt}.html\">next</a>"
    fout.close
  end
end
