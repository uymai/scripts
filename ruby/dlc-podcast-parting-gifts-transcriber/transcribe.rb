#!/usr/bin/env ruby
require 'json'
require 'yaml'

SECRETS = YAML.load(File.read('secrets.yml'))
PODCAST_ENDPOINT = 'https://director.5by5.tv/d/dlc/5by5.cachefly.net/audio/broadcasts/dlc/2020/'
WATSON_ENDPOINT = 'https://stream.watsonplatform.net/speech-to-text/api/v1/recognize'
OUTPUT_DIR = 'output'

def download_episode uri
  puts 'downloading episode...'

  @current_file_name = File.join(OUTPUT_DIR, File.basename(uri.path))

  # delete any file first to make sure we get the proper name
  `rm -f #{@current_file_name}`

  # download the thing
  `wget -q #{uri.to_s} -P #{OUTPUT_DIR}`

  if not File.exists?(@current_file_name)
    puts `Couldn't download file at address #{uri.to_s}`
    exit 1
  end

  File.new(@current_file_name)
end

def cut_section file
  puts 'extracting parting gifts section...'
  @current_file_name.insert(-5, '-partinggifts')

  # strip the last 10 minutes of the file and saves it separately
  `ffmpeg -loglevel quiet -sseof -10:00 -i #{file.path} -codec copy -y #{@current_file_name}`
  File.new(@current_file_name)
end

def transcribe_section file
  puts 'transcribing section...'
  text_file_name = @current_file_name.sub('.mp3', '.txt')
  api_key = SECRETS['watson_api_key']

  # send the parting gifts section do the watson service and saves the result
  `curl -X POST -s -u "apikey:#{api_key}" -H "Content-Type: audio/mp3" --data-binary @#{file.path} "#{WATSON_ENDPOINT}" -o #{text_file_name}`
  File.new(text_file_name)
end

def extract_text transcription_file
  puts 'extracting text paragraphs...'
  result = JSON.parse(File.read(transcription_file))

  # extract the text bits from the transcription object
  paragraphs = result['results'].map do |res|
    res['alternatives'][0]['transcript']
  end
end

def differentiate_guests
end

def output_text paragraphs
  @current_file_name.insert(-5, '-transcription')
  @current_file_name.sub!('mp3', 'txt')

  IO.write(@current_file_name, paragraphs.join("\n\n"))
  puts 'done. created file ' << @current_file_name
end

ep_number = ARGV[0]
if ep_number.nil?
  puts 'No episode number. Exiting...'
  exit
end

puts "About to transcribe episode #{ep_number} parting gifts"
puts 'Continue? [yN]'

confirmation = STDIN.gets.chomp

if confirmation != 'y' and confirmation != 'Y'
  puts 'No confirmation. Exiting...'
  exit
end

if SECRETS.nil? or SECRETS == false or SECRETS['watson_api_key'].nil? or SECRETS['watson_api_key'].length == 0
  puts 'No watson API key found. Check you secrets.yml file.'
  exit 1
end

Dir.mkdir(OUTPUT_DIR) unless Dir.exists?(OUTPUT_DIR)

episode_file = download_episode URI.join(PODCAST_ENDPOINT, 'dlc-' << ep_number << '.mp3')
pg_section_file = cut_section episode_file
transcription_result = transcribe_section pg_section_file
paragraphs = extract_text transcription_result
output_text paragraphs
