require 'line/bot'
require "net/http"
require "json"
require "uri"

class WebhookController < ApplicationController
  CHESS_API_URL = 'https://api.chess.com/pub/puzzle'
  CHESS_PIECES = ['K', 'Q', 'B', 'N', 'R', 'P']
  CHECK_NOTATIONS = ['+', '#']
  CAPTURE_NOTATION = 'x'

  protect_from_forgery except: [:callback] # CSRF対策無効化

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def get_error_text_object
    {
      type: 'text',
      text: '問題が発生しました。しばらくしてから試してください'
    } 
  end

  def normalize_move move
    move.strip!

    # "1.Ra5" とかの "1." はいらない && 棋譜に "."は登場しない
    if move.include? "."
      last_dot = move.rindex('.', -1)
      move.slice!(0, last_dot + 1)
    end

    #ポーンが省略されてる場合はつける
    if CHESS_PIECES.none? { |piece| move.include?(piece) }
      move = move.insert(-3, 'P')
    end

    move
  end

  def parse_move move
    # Pがついてる前提の時、最初の一文字は駒
    piece = move.slice(0, 1)

    # "+", "#" を省いたときの末尾2文字はマス目(多分)
    location = move.delete('#+').slice(-2, 2)

    # チェックメイトに関する表記は最後の1文字にしかつかない
    check_notation = nil
    CHECK_NOTATIONS.each do |mark| 
      if(move.slice(-1, 1) == mark) 
        check_notation = mark
      end
    end

    captured = move.include?(CAPTURE_NOTATION)
    
    # Pがついてる前提の時、'x', '+', '#'を省いたときに4文字ある場合は2文字目が初期位置を表す記号
    original_location = nil
    simplest_form = move.delete('x+#')
    if simplest_form.length == 4
      original_location = simplest_form.slice(1)
    end

    return {
      piece: piece,
      location: location,
      check_notation: check_notation,
      captured: captured,
      original_location: original_location,
    }
  end

  def correct_move?(answer_move, user_move)
    if answer_move[:piece] + answer_move[:location] != user_move[:piece] + user_move[:location]
      return false
    end

    # ユーザーが細かい情報まで打ち込んだ時だけチェックする
    if user_move[:captured]
      if !answer_move[:captured]
        return false
      end
    end

    if user_move[:check_notation].present? && user_move[:check_notation] != answer_move[:check_notation]
      return false
    end

    if user_move[:original_location].present? && user_move[:original_location] != answer_move[:original_location]
      return false
    end

    true
  end

  def get_moves pgn
    lines = pgn.lines(chomp: true)

    #空行の次が指し手
    empty_line_index = lines.find_index('');
    lines[empty_line_index + 1].split(' ')
  end

  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      head 470
    end

    events = client.parse_events_from(body)
    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          url = URI.parse(CHESS_API_URL)

          begin
            res = Net::HTTP.get_response(url)
            case res
            when Net::HTTPSuccess
              data = JSON.parse(res.body, symbolize_names: true)
              moves = get_moves(data[:pgn])
              moves[0]
              user_message = event.message['text']

              if user_message == '問題だして'
                message = {
                  type: 'image',
                  originalContentUrl: data[:image],
                  previewImageUrl: data[:image]
                }
              else 
                user_move = parse_move(normalize_move(user_message))
                answer_move = parse_move(normalize_move(moves[0]))

                if correct_move?(answer_move, user_move)
                  message = {
                    type: 'text',
                    text: '正解！'
                  }
                else
                  message = {
                    type: 'text',
                    text: '間違ってる。。'
                  }
                end
              end
            else
              message = get_error_text_object
            end
          rescue => e
            message = get_error_text_object
          end

          client.reply_message(event['replyToken'], message)
        end
      end
    end
    head :ok
  end

  private :client, :get_error_text_object, :normalize_move, :get_moves
end
