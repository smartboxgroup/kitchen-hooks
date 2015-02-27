require 'ridley'

require 'set'


class SyncServers
  attr_reader :status

  def initialize knives, cached_nodes={}
    @knives  = knives
    @started = Time.now
    @cached_nodes = Hash.new { |h,k| h[k] = 0.0 }
    @cached_nodes.merge! cached_nodes
    @status = sync_servers.merge \
      elapsed: Time.now - @started rescue nil
  end

  def cached_nodes
    Hash[@cached_nodes]
  end


private

  def ridleys
    @ridleys ||= @knives.map do |knife|
      Ridley.from_chef_config(knife)
    end
  end


  def search_nodes
    @clients = {}
    bad_ridleys = []

    @search_nodes ||= ridleys.each_with_index.pmap(4) do |ridley, i|
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

    return @search_nodes
  end


  def updated_and_deleted_nodes
    @all_nodes ||= search_nodes.group_by(&:name).pmap do |name, copies|
      copies.sort_by do |c|
        time = c.automatic.ohai_time
        time.is_a?(Float) ? time : -1.0
      end.last
    end

    @updated_nodes ||= @all_nodes.select do |n|
      n.automatic.ohai_time.to_f > @cached_nodes[n.name]
    end

    @deleted_nodes ||= @cached_nodes.keys - @all_nodes.map(&:name)

    return @updated_nodes, @deleted_nodes
  end


  def sync_servers
    nodes, deleted = updated_and_deleted_nodes
    failures = Set.new

    nodes.shuffle.peach(8) do |n|
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

      if failures.include? n.name
        puts 'ERROR: Node sync failed for node "%s"' % n.name
      else
        puts 'Synced node "%s"' % n.name
      end
    end unless @ridleys.length == 1

    successes = []
    nodes.each do |n|
      next if failures.include? n.name
      @cached_nodes[n.name] = n.automatic.ohai_time.to_f
      successes << n.name
    end

    deleted.each do |n|
      puts 'Deleting node "%s"' % n
      ridleys.peach(4) do |ridley|
        ridley.node.delete n rescue \
          puts('WARNING: Could not delete node "%s"' % n)
      end
    end

    return {
      deleted: deleted,
      failures: failures,
      successes: successes,
      num_successes: successes.length,
      num_failures: failures.length,
      num_deletions: deleted.length,
      num_nodes: nodes.length
    }
  end

end