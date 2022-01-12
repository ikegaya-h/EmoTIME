require 'sinatra'
require 'line/bot'

#clientの設定情報をgitignoreできるように別ファイルに切り出す（予定）
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
          return client.reply_message(event['replyToken'], message)
        end
        #ファイルのIDでLINEサーバからtxtデータを取得する
          #文字のエンコードによっては文字化けするかも？
        response = client.get_message_content(event.message['id']) #引数にevent.message['id']を指定することでURI生成＋ファイルをGETリクエスト
        case response
        when Net::HTTPSuccess then
          #response.body -> Strings
          txt = response.body.lines(chomp: true)
          #配列を整形
          #保存日時と改行のみの行を削除
          txt.each do |s|
            if "\r" == s
              txt.delete(s)
            elsif /保存日時：20[0-9][0-9]\/[01][0-2]\/[0-3][0-9] [0-2][0-9]:[0-5][0-9]/ === s
              txt.delete(s)
            end
          end

          #時系列と発言者と発言内容を二重配列に整頓
          #行が変化する加工が完了したら実行
          count = 0
          txt.each do |s|
            if /[0-2][0-9]:[0-5][0-9]/ === s
              txt[count] = s.split(/\t/)
            end
            count += 1
          end

        #クイックリプライにクライアントが過去に送信したメッセージを入れる
          #ユーザーを取得
          user = User.find_by!(user: client.channel_id)
          #配列の時系列の初期値を保存
          count = 2
          if txt[2][1] = txt[0]
            while txt[count][1] = txt[0] do
              send_message += txt[count][2]\n
              count += 1
            end
            until txt[count][1] = txt[0] do
              set_message += txt[count][2]\n
              count += 1
            end
          else
            send_message = "スタート"
            until txt[count][1] = txt[0] do
              set_message += txt[count][2]\n
              count += 1
            end
          end
          sender_name = txt[count][1]
          user.replay_point = count
          #後にファイルを呼び出すときのメッセージIDを保存
          user.file_id = event.message['id']
          user.save!

        #一番初めのメッセージを送信
          #初めのメッセージがクライアントの場合"スタート"のメッセージから始める
          message = {
            type: 'text',
            text: send_message,
            sender: {
              name: sender_name
            }
            quickReply: {
              items: [
                {
                  type: "action",
                  action: {
                    type: "message",
                    label: "返信",
                    text: set_message
                  }
                }
              ]
            }
          }
          client.reply_message(event['replyToken'], message)
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