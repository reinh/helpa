# Controller for the helpa leaf.
gem 'activerecord', "2.1.2"
require 'activerecord'

ActiveRecord::Base.establish_connection(YAML::load(File.open("config/seasons/helpa/database.yml", "r+"))["production"])
class Controller < Autumn::Leaf
  
  def gitlog_command(stem, sender, reply_to, msg)
    `git log -1`.split("\n").first
  end

  def tip_command(stem, sender, reply_to, command, options={})
    return unless authorized?(sender[:nick])
    if tip = Tip.find_by_command(command.strip) 
      tip.text.gsub!("{nick}", sender[:nick])
      message = tip.text
      message = "#{options[:directed_at]}: #{message}" if options[:directed_at]
      stem.message(message, reply_to)          
    else
      stem.message("I could not find that command. If you really want that command, go to http://rails.loglibrary.com/tips/new?command=#{command} and create it!", sender[:nick])
    end    
  end
  
  def join_command(stem, sender, reply_to, msg)
    join_channel(msg) if authorized?(sender[:nick])
  end

  def part_command(stem, sender, reply_to, msg)
    leave_channel(msg) if authorized?(sender[:nick])
  end
  
  def help_command(stem, sender, reply_to, msg)
    if authorized?(sender[:nick])
      if msg.nil?
        stem.message("A list of all commands can be found at http://rails.loglibrary.com/tips", sender[:nick])
      else
        comnand = msg.split(" ")[1]
        if tip = Tip.find_by_command(command)
          stem.message(" #{tip.command}: #{tip.description} - #{tip.text}", sender[:nick])
        else  
          stem.message("I could not find that command. If you really want that command, go to http://rails.loglibrary.com/tips/new?command=#{command} and create it!", sender[:nick])
        end
      end
    end
  end
  
  def update_api_command(stem, sender, reply_to, msg)
    return unless authorized?(sender[:nick])
    require 'hpricot'
    require 'net/http'
    stem.message("Updating API index", sender[:nick])
    Constant.delete_all
    Entry.delete_all
    # Ruby on Rails Methods
    update_api("Rails", "http://api.rubyonrails.org")
    update_api("Ruby", "http://www.ruby-doc.org/core")
    
    stem.message("Updated API index! Use the !lookup <method> or !lookup <class> <method> to find what you're after", sender[:nick])
    return nil
  end
  
  def lookup_command(stem, sender, reply_to, msg, opts={})
    return if msg.blank?
      parts = msg.split(" ") if msg.include?(" ")
      parts ||= msg.split("#") if msg.include?("#")
      parts ||= [msg]
    
    # Is the first word a constant?
    if /^[A-Z]/.match(parts.first)
      constant = Constant.find_by_name(parts.first)
      constant ||= Constant.find_by_name(parts.first + "::ClassMethods")
      if constant
        entry = constant.entries.find_by_name(parts.last)
        if entry
          constant.increment!("count")
          entry.increment!("count")
          message = "#{constant.name}##{entry.name}: #{entry.url}"
          message = send_lookup_message(stem, message, reply_to, opts[:directed_at])
        else
          if parts.last != parts.first
            entries = Entry.find_all_by_name(parts.last)
            if entries.empty?
              stem.message("Could not find any entry with the name #{parts.last} anywhere in the API.", sender[:nick])
            else
              classes = entries.map(&:constant).sort_by { |c| c.count }.last(5).map(&:name)
              stem.message("Could not find #{parts.last} within the scope of #{parts.first}! Perhaps you meant: #{classes.join(", ")}", sender[:nick])
            end
          else
            constant.increment!("count")
            message = "#{constant.name}: #{constant.url}"
            message = send_lookup_message(stem, message, reply_to, opts[:directed_at])
          end
        end      
      else  
        stem.message("Could not find constant #{parts.first} or #{parts.first}::ClassMethods in the API!", sender[:nick])
      end
    else
      # The first word is a method then
      entries = Entry.find_all_by_name(parts.first)
      if entries.size == 1
        entry = entries.first  
        constant = entry.constant
        constant.increment!("count")
        entry.increment!("count")
        message = "#{constant.name}##{entry.name}: #{entry.url}"
        message = send_lookup_message(stem, message, reply_to, opts[:directed_at])
      elsif entries.size > 1
        classes = entries.map(&:constant).sort_by { |c| c.count }.last(5).map(&:name)
        stem.message("Found multiple entries for #{parts.first}, please refine your query by specifying one of these classes (top 5 shown): #{classes.join(", ")} or another class", sender[:nick])
      else
        stem.message("Could not find any entry with the name #{parts.last} anywhere in the API.", sender[:nick])
      end
    end
  end
  
  def google_command(stem, sender, reply_to, msg, opts={})
    google("http://www.google.com/search", stem, sender, msg, reply_to, opts)
  end
  
  alias :g_command :google_command 
  
  def gg_command(stem, sender, reply_to, msg, opts={})
    google("http://www.letmegooglethatforyou.com/", stem, sender, msg, reply_to, opts)
  end
  
  private
  
  def send_lookup_message(stem, message, reply_to, directed_at=nil)
    message = "#{directed_at}: " + message  if directed_at
    stem.message(message, reply_to)  
  end
  
  def update_api(name, url)
    Api.find_or_create_by_name_and_url(name, url)
    update_methods(Hpricot(Net::HTTP.get(URI.parse("#{url}/fr_method_index.html"))), url)
    update_classes(Hpricot(Net::HTTP.get(URI.parse("#{url}/fr_class_index.html"))), url)
  end
  
  def update_methods(doc, prefix)
    doc.search("a").each do |a|
      names = a.inner_html.split(" ")
      method = names[0]
      name = names[1].gsub(/[\(|\)]/, "")
      # The same constant can be defined twice in different APIs, be wary!
      url = prefix + "/classes/" + name.gsub("::", "/") + ".html"
      constant = Constant.find_or_create_by_name_and_url(name, url)
      constant.entries.create!(:name => method, :url => prefix + "/" + a["href"])
    end
  end
  
  def update_classes(doc, prefix)
    doc.search("a").each do |a|
      constant = Constant.find_or_create_by_name_and_url(a.inner_html, a["href"])
    end
  end
  
  def google(host, stem, sender, msg, reply_to, opts)
    return unless authorized?(sender[:nick])
    message = "#{host}?q=#{msg.split(" ").join("+")}"
    message = opts[:directed_at] + ": #{message}" if opts[:directed_at]
    return message
  end
  
  def i_am_a_bot
    ["I am a bot! Please do not direct messages at me!",
     "FYI I am a bot.",
     "Please go away. I'm only a bot.",
     "I am not a real person.",
     "No I can't help you.",
     "Wasn't it obvious I was a bot?",
     "I am not a werewolf; I am a bot.",
     "I'm botlicious.",
     "Congratulations! You've managed to message a bot.",
     "I am a bot. Your next greatest discovery will be that the sky is, in fact, blue."     
     ].rand
  end
  
  def authorized?(nick)
    User.find_by_login(nick.downcase)
  end
  
  def did_receive_private_message(stem, sender, message)
    command = /^!(.*?)\s(.*?)$/.match(message)
    if command
      if command[1] == "lookup"
        lookup_command(stem, sender, sender[:nick], command[2])
      elsif command[1] == "say"
        parts = command[2].split(" ")
        channel = parts.first
        stem.message(parts[1..-1].join(" "), channel)
      end
    end
  end

  def did_receive_channel_message(stem, sender, channel, message)
    # try to match a non-existent command which might be a tip
    if m = /^(([^:]+):)?\s?!([^\s]+)\s?(.*)?/.match(message)
      cmd_sym = "#{m[3]}_command".to_sym
      # if we don't respond to this command then it's likely a tip
      if respond_to?(cmd_sym)
        if !m[2].nil?
          send(cmd_sym, stem, sender, channel, m[4], { :directed_at => m[2] })
        end
      else
        tip_command(stem,sender,channel,m[3], {:directed_at => m[2]})
      end
    end
    
    if message.match(/^helpa[:|,]/)
      stem.message(i_am_a_bot, sender[:nick])
    end
  end
end
