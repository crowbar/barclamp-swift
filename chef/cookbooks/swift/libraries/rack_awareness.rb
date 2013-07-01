require 'chef'
#require 'pp'

class Rack_awareness
  class By_switch

    def initialize(node)
      @node=node
      @rr_counter=0
      @switch_list = self.get_switch_list()
      @switch_list = self.switch_to_zone() if @switch_list.size != 0
    end

    def get_switch_list()
        switch_list=Hash.new()
        #get all swift nodes
        env_filter = " AND swift_config_environment:#{@node[:swift][:config][:environment]}"
        nodes = Chef::Search::Query.new.search(:node, "roles:swift-storage#{env_filter}")[0]
        #PP.pp(nodes.size, $>, 40)
        nodes.each do |n|
            sw_name=self.get_node_sw(n)
            if sw_name == -1
                next
            end
            if switch_list["#{sw_name}"].nil?
                switch_list["#{sw_name}"]=Hash.new()
                switch_list["#{sw_name}"]["nodes"]=[]
            end
            if not switch_list["#{sw_name}"]["nodes"].include?(n.name)
                switch_list["#{sw_name}"]["nodes"] << n.name
            end
        end
        return switch_list
    end

    def get_node_sw(n)
            #get switch for storage iface
            storage_ip = Swift::Evaluator.get_ip_by_type(n, :storage_ip_expr)
            #get storage iface
            iface=""
            n[:network][:interfaces].keys.each do |ifn|
                if n[:network][:interfaces]["#{ifn}"][:addresses].has_key?(storage_ip)
                    iface=ifn
                    break
                end
            end
            #this may lead us to eth0, or eth0.123, or even br0, br0.123, vlan231 and so on, so
            #TODO: some cases for complicated network configuration with bridges, vlans
            case iface
            when /eth[0-9]*.*/
               iface=iface[/^eth[0-9]*/]
            else
               #fallback to something default
               iface=n[:crowbar_ohai][:switch_config].keys[0]
            end
            sw_name=n[:crowbar_ohai][:switch_config][iface][:switch_name]
    end

    def switch_to_zone()
        #set switch to zone by round-robin
        zone_count=@node[:swift][:zones]
        zone_list=zone_count.times.to_a
        switch_list=@switch_list
        switch_list.keys.each do |sw_name|
             switch_list["#{sw_name}"]["zones"]=[] if not switch_list["#{sw_name}"].has_key?("zones")
        end

        if switch_list.size >= zone_list.size
            #some switches may have same zone with each other
            switch_list.keys.sort.each do |sw_name|
                zone=zone_list.shift
                zone_list=zone_count.times.to_a if zone_list.size == 0
                switch_list["#{sw_name}"]["zones"] << zone
            end
        else
            #some switches may have more than 1 zone
            sw_iter=switch_list.keys.sort
            zone_list.each do |zone|
                sw_name=sw_iter.shift
                sw_iter=switch_list.keys.sort if sw_iter.size == 0
                switch_list["#{sw_name}"]["zones"] << zone
            end
        end

        return switch_list
    end


    def node_to_zone(params)
        n=params[:target_node]
        sw_name=self.get_node_sw(n)
        zone_count=@node[:swift][:zones]
        if sw_name == -1
            #just assign to somewhere
            zone=@rr_counter % zone_count
            @rr_counter += 1
            return zone
        end
        available_zones=@switch_list["#{sw_name}"]["zones"]
        zone=@rr_counter % available_zones.size
        zone=available_zones[zone]
        @rr_counter += 1
        return zone
    end

  end
end

