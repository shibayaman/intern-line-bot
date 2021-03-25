require 'line/bot'

class WebhookController < ApplicationController
  protect_from_forgery except: [:callback] # CSRF対策無効化

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def requesting_puzzle?(text)
    text.match(/^(問題|もんだい)[出だ]して$/)
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
          if requesting_puzzle? event.message['text']
            message = {
              type: 'image',
              #　ランダムな猫の画像を返してくれるURL
              originalContentUrl: 'https://placekitten.com/400/400',
              previewImageUrl: 'https://placekitten.com/200/200'
            }
          elsif 
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
end
