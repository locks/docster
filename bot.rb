#! /usr/bin/env ruby

require 'bundler'
Bundler.require(:default)
if ENV['BOT_ENV'] == 'development'
  Bundler.require(:development)
  Dotenv.load
end
require 'net/http'
require 'json'

docs_uri = URI('http://builds.emberjs.com/release/ember-docs.json')

ember_docs = JSON.parse Net::HTTP.get(docs_uri)
$class_list = ember_docs['classes']
$valid_classes = {}

$class_list.keys.each do |class_name|
  $valid_classes[class_name.downcase] = class_name
  $valid_classes[class_name.gsub(/\AEmber\./, '').downcase] = class_name
end
$tag = '1.7.0'
class ApiPlugin
  include Cinch::Plugin

  match /api/, method: :api
  match /help/, method: :help
  # match /source/, method: :source

  def help(m)
    m.reply 'Commands:'
    m.reply ' !api <class name> - Links to documentation and source for the given class'
  end

  def api(m)
    debug "api"
    class_name = m.message.match(/!api (.*)/)[1]

    if class_name = $valid_classes[class_name.downcase]
      m.reply "Docs: http://emberjs.com/api/classes/#{class_name}.html"

      class_details = $class_list[class_name]
      file_name = class_details['file'][3..-1]
      line = class_details['line']
      url = "https://github.com/emberjs/ember.js/blob/v#{$tag}/#{file_name}#L#{line}"
      m.reply "Source: #{url}"
    else
      m.reply 'I blame rwjblue'
    end
  end

end

bot = Cinch::Bot.new do
  configure do |c|
    c.server = "irc.freenode.org"
    c.channels = ["#dockyard", "#bostonember"]
    c.nick = "docster"
    c.password = ENV['PASSWORD']
    c.plugins.plugins = [ApiPlugin]
  end
end

bot.start
