require 'line/bot'
require "net/http"
require "json"
require "uri"

class WebhookController < ApplicationController
  CHESS_API_URL = 'https://api.chess.com/pub/puzzle'

  protect_from_forgery except: [:callback] # CSRF対策無効化

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def get_error_text_object
    return {
      type: 'text',
      text: '問題が発生しました。しばらくしてから試してください'
    } 
  end

  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      head 470
    end

    events = client.parse_events_from(body)
    events.each { |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          if event.message['text'] == '問題だして'
            url = URI.parse(CHESS_API_URL)

            begin
              res = Net::HTTP.get_response(url)

              case res
                when Net::HTTPSuccess
                  data = JSON.parse(res.body, symbolize_names: true)
                  message = {
                    type: 'image',
                    originalContentUrl: data[:image],
                    previewImageUrl: data[:image]
                  }
                else
                  message = get_error_text_object
                end
            rescue => e
              message = get_error_text_object
            end
          else 
            message = {
              type: 'text',
              text: 'すみません。よくわかりません。'
            }
          end
          client.reply_message(event['replyToken'], message)
        end
      end
    }
    head :ok
  end

  private :client, :get_error_text_object
end
