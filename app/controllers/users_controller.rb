class UsersController < ApplicationController
  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_id = ENV["LINE_CHANNEL_ID"]
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      error 400 do 'Bad Request' end
    end

    send_message = ""
    set_message = ""

    events = client.parse_events_from(body)
    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          user = User.find_by!(user: client.channel_id)
          response = client.get_message_content(user.file_id)
          case response
          when Net::HTTPSuccess
            txt = []
            response.body.each_line { |line|
              txt << line.gsub!(/\n/) { '' }
            }
            txt.map { |n| n.force_encoding('utf-8') }
            txt[0] = txt[0].delete("[LINE] ")
            txt[0] = txt[0].delete("とのトーク履歴")
            txt.each do |s|
              if "" == s
                txt.delete(s)
              elsif /保存日時：20[0-9][0-9]\/[01][0-2]\/[0-3][0-9] [0-2][0-9]:[0-5][0-9]/ === s
                txt.delete(s)
              end
            end
            count = 0
            txt.each do |s|
              case s
              when /[0-2][0-9]:[0-5][0-9]/
                txt[count].gsub!(/\"/) { '' }
                txt[count] = s.split(/\t/)
              when /\"/
                previous = count - 1
                txt[count] = [txt[previous][0], txt[previous][1], txt[count].gsub!(/\"/) { '' }]
              end
              count += 1
            end
            count = user.replay_point
            if client.reply_message == txt[user.resending_point][1]
              while txt[count][1] == user.official_title do
                send_message += "#{txt[count][2]}\n"
                count += 1
              end
              until txt[count][1] == user.official_title do
                set_message += "#{txt[count][2]}\n"
                count += 1
              end
              user.resending_point = user.replay_point
              unless set_message
                set_message = "~end~"
                user.replay_point = 2
              end
              user.save!
            else
              count = user.resending_point
              while txt[count][1] == user.official_title do
                send_message += "#{txt[count][2]}\n"
                count += 1
              end
              until txt[count][1] == user.official_title do
                set_message += "#{txt[count][2]}\n"
                count += 1
              end
            end
            message = {
              type: 'text',
              text: send_message,
              sender: {
                name: user.official_title
              },
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
        when Line::Bot::Event::MessageType::File
          unless /とのトーク.txt/ === event["message"]["fileName"]
            message = {
              type: 'text',
              text: "指定のファイルと異なります"
            }
            return client.reply_message(event['replyToken'], message)
          end
          response = client.get_message_content(event.message['id'])
          case response
          when Net::HTTPSuccess
            txt = []
            response.body.each_line { |line|
              txt << line.gsub!(/\n/) { '' }
            }
            txt.map { |n| n.force_encoding('utf-8') }
            #配列を整形
            txt[0] = txt[0].delete("[LINE] ")
            txt[0] = txt[0].delete("とのトーク履歴")
            #1.保存日時と改行のみの行を削除
            txt.each do |s|
              if "" == s
                txt.delete(s)
              elsif /保存日時：20[0-9][0-9]\/[01][0-2]\/[0-3][0-9] [0-2][0-9]:[0-5][0-9]/ === s
                txt.delete(s)
              end
            end
            #2.時系列と発言者と発言内容を二重配列に整頓
            #行が変化する加工が完了したら実行
            count = 0
            txt.each do |s|
              case s
              when /[0-2][0-9]:[0-5][0-9]/
                txt[count].gsub!(/\"/) { '' }
                txt[count] = s.split(/\t/)
              when /\"/
                previous = 0
                previous = count - 1
                txt[count] = [txt[previous][0], txt[previous][1], txt[count].gsub!(/\"/) { '' }]
              end
              count += 1
            end
            #クイックリプライにクライアントが過去に送信したメッセージを入れる
            #1.ユーザーを取得
            user = User.find_by!(user_id: event["source"]["userId"])
            #送られてきたtxtファイルのトークルーム名を役名として保存
            user.official_title = txt[0]
            #2.配列の時系列の初期値を保存
            count = 2
            user.resending_point = count
            if txt[count][1] == user.official_title
              while txt[count][1] == user.official_title do
                send_message += "#{txt[count][2]}\n"
                count += 1
              end
              until txt[count][1] == user.official_title do
                set_message += "#{txt[count][2]}\n"
                count += 1
              end
            else
              send_message = "スタート"
              until txt[count][1] == user.official_title do
                set_message += "#{txt[count][2]}\n"
                count += 1
              end
            end
            user.replay_point = count
            user.file_id = event.message['id']
            user.save!
            message = {
              type: 'text',
              text: send_message,
              sender: {
                name: user.official_title
              },
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
        end
      when Line::Bot::Event::Follow 
        user = User.new
        user.user_id = event["source"]["userId"]
        user.save!
      when Line::Bot::Event::Unfollow 
        user = User.find_by!(user_id: event["source"]["userId"])
        user.destroy!
      end
    end
    "ok"
  end
end
