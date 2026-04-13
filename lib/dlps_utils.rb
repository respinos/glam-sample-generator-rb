# Stub for DlpsUtils module
module DlpsUtils
  # Ruby version of SetLocalOrRemoteMode
  def self.set_local_or_remote_mode(requesting_host, coll_host)
    mode = 'local'
    requesting_host = requesting_host.sub(/:\d+$/, '')
    coll_host = coll_host.sub(/:\d+$/, '')
    if requesting_host != coll_host
      mode = 'remote' unless coll_host == 'localhost'
    end
    mode
  end

  # Remove well-formed tag pairs from tag_stack (modifies in place)
  def self.remove_well_formed_nodes(tag_stack, left_ptr = 0, recursion_ct = 0)
    while tag = tag_stack[left_ptr]
      if !tag.start_with?('/')
        right_ptr = left_ptr + 1
        pair_removed = false
        while !pair_removed && right_ptr < tag_stack.size
          possible_mate = tag_stack[right_ptr]
          if possible_mate == tag
            recursion_ct += 1
            raise 'Infinite recursion. XML not well-formed.' if recursion_ct >= 1000
            remove_well_formed_nodes(tag_stack, right_ptr, recursion_ct)
          elsif possible_mate == "/#{tag}"
            tag_stack.slice!(left_ptr, right_ptr - left_ptr + 1)
            pair_removed = true
          else
            right_ptr += 1
          end
        end
        if pair_removed
          left_ptr = 0
        else
          left_ptr += 1
        end
      else
        left_ptr += 1
      end
    end
  end

  # Make remaining tags well-formed (modifies s in place)
  def self.make_well_formed_nodes(tag_stack, s)
    while tag_stack.any?
      tag = tag_stack[0]
      if tag.start_with?('/')
        open_tag = tag[1..-1]
        s.prepend("<#{open_tag}>")
        tag_stack.shift
      else
        tag = tag_stack.pop
        if tag && !tag.start_with?('/')
          s << "</#{tag}>"
        else
          raise "Malformed XML: #{tag_stack.join(' ')}"
        end
      end
    end
  end

  # Twigify: make XML fragment well-formed by closing open tags and opening unmatched close tags
  def self.twigify(s)
    str = s.dup
    tag_stack = str.scan(/<([^>]+)>/).flatten.reject { |t| t =~ /.+?\/$/ }
    tag_stack.map! { |t| t.sub(/\s+.*$/, '') }
    remove_well_formed_nodes(tag_stack)
    make_well_formed_nodes(tag_stack, str)
    str
  end
end
