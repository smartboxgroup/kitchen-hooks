require 'ridley'

require 'set'


class SyncServers
  attr_reader :status


  def initialize knives
    @knives  = knives
    @started = Time.now
    @status  = sync_servers.merge \
      elapsed: Time.now - @started rescue nil
  end



private

  def ridleys
    @ridleys ||= @knives.map do |knife|
      Ridley.from_chef_config(knife)
    end
  end


  def all_nodes
    @clients ||= {}
    bad_ridleys = []

    @all_nodes ||= ridleys.each_with_index.pmap(4) do |ridley, i|
      clients = ridley.client.all

      begin
        nodes = ridley.partial_search(:node, '*:*', %w[ ohai_time ])
      rescue
        puts 'WARNING: No partial search, skipping knife'
        bad_ridleys << i
        nodes = []
      end

      nodes.map do |n|
        c = clients.select { |c| c.name == n.name }.shift
        @clients[n.name] = c unless c.nil?
        n
      end
    end.flatten

    bad_ridleys.sort.reverse.each do |idx|
      @ridleys.delete_at idx
    end

    return @all_nodes
  end


  def merged_nodes
    @merged_nodes ||= all_nodes.group_by(&:name).pmap do |_, copies|
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

        c = @clients[n.name]
        next if c.nil?
        ridley.client.create(c) \
        rescue ridley.client.update(c) \
        rescue puts('WARNING: Client sync failed for node "%s"' % n.name)
      end

      puts 'Synced node "%s"' % n.name
    end unless @ridleys.length == 1

    puts 'Sync completed'
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