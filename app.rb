require 'sinatra'
require 'line/bot'

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_id = ENV["LINE_CHANNEL_ID"]
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

post '/callback' do
  body = request.body.read #送られてきたJSONを開いてbodyに格納

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body) #bodyの中身(JSON)をイベントだけ取り出してhashにする
  events.each do |event| #文字通り送られたイベントhashを一つづつ入れている
    case event
    when Line::Bot::Event::Message #eventの文字とモジュールの定数が一致しているか比較している
      case event.type #セッターとゲッターを自動で定義するメソッドによって中身の読み書きができる
      when Line::Bot::Event::MessageType::Text
        #クイックリプライにセットしたメッセージと一致しているか確認
          #やりとりの最後なら終了メッセージを送信
          #クイックリプライと一致していなければメッセージを再送
        #どこまでやり取りしたかをDBに保存
        #返信メッセージを生成
        message = {
          type: 'text',
          text: event.message['text']
        }
        client.reply_message(event['replyToken'], message)
      when Line::Bot::Event::MessageType::File
        #ファイル名が.txtになっているか確認
        unless /[LINE] [!-~]{1,}とのトーク.txt/ === event.message.fileName
          message = {
            type: 'text',
            text: "指定のファイルと異なります"
          }
          client.reply_message(event['replyToken'], message)
        end
        #ファイルのIDでLINEサーバからtxtデータを取得する
          #文字のエンコードによっては文字化けするかも？
        response = client.get_message_content(event.message['id']) #引数にevent.message['id']を指定することでURI生成＋ファイルをGETリクエスト
        case response
        when Net::HTTPSuccess then
          tf = Tempfile.open("content")
        #取得したtxtファイルを加工
        #クイックリプライにクライアントが過去に送信したのメッセージを入れる
        #一番初めのメッセージを送信
          #初めのメッセージがクライアントの場合"スタート"のメッセージから始める
        end

      when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
        response = client.get_message_content(event.message['id'])
        tf = Tempfile.open("content")
        tf.write(response.body)
      end
    end
    when Line::Bot::Event::Follow
      #LINEのユーザーIDを元にDBにユーザー作成
    end
    when Line::Bot::Event::Unfollow
      #DBからユーザーを削除
    end
  end

  # Don't forget to return a successful response
  "OK"
end