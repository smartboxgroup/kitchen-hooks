require 'ridley'

require 'set'


class SyncServers
  attr_reader :status


  def initialize knives
    @knives = knives
    @started = Time.now
    @status = sync_servers.merge \
      elapsed: Time.now - @started
  end


private

  def ridleys
    @ridleys ||= @knives.map do |knife|
      Ridley.from_chef_config(knife)
    end
  end

  def all_nodes
    @all_nodes ||= ridleys.flat_map do |ridley|
      ridley.partial_search(:node, '*:*', %w[ ohai_time ])
    end
  end


  def merged_nodes
    @merged_nodes ||= all_nodes.group_by(&:name).pmap do |name, copies|
      copies.sort_by { |c| c.automatic.ohai_time }.last
    end
  end


  def sync_servers
    nodes = merged_nodes
    failures = Set.new

    nodes.peach(8) do |n|
      n.reload
      ridleys.peach(4) do |ridley|
        ridley.node.create(n) \
        rescue ridley.node.update(n) \
        rescue failures << n.name
      end
      puts 'Synced node "%s"' % n.name
    end

    return {
      failures: failures,
      num_successes: nodes.length - failures.length,
      num_failures: failures.length,
      num_nodes: nodes.length
    }
  rescue
    return nil
  end

end