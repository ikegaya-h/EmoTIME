class UsersController < ApplicationController
  def client
    @client ||= Line::Bot::Client.new do |config|
      config.channel_id = ENV["LINE_CHANNEL_ID"]
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    end
  end

  def callback
    body = request.body.read

    signature = request.env["HTTP_X_LINE_SIGNATURE"]
    unless client.validate_signature(body, signature)
      error 400 do "Bad Request" end
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
            response.body.each_line do |line|
              txt << line.force_encoding("utf-8")
            end
            txt.map { |n| n.gsub!(/\r\n/) { '' } }
            txt[0] = txt[0].delete("[LINE] ")
            txt[0] = txt[0].delete("とのトーク履歴")
            txt.each do |s|
              if s == ""
                txt.delete(s)
              elsif /保存日時：20[0-9][0-9]\/[01][0-2]\/[0-3][0-9] [0-2][0-9]:[0-5][0-9]/ === s
                txt.delete(s)
              end
            end
            count = 0
            txt.each do |s|
              if /[0-2][0-9]:[0-5][0-9]/ === s
                txt[count].gsub!(/\"/) { '' }
                txt[count] = s.split(/\t/)
              elsif /\"/ === s
                previous = count - 1
                txt[count].gsub!(/\"/) { '' }
                txt[count] = [txt[previous][0], txt[previous][1], txt[count]]
              end
              count += 1
            end
            count = user.replay_point
            if client.reply_message == txt[user.resending_point][1]
              while txt[count][1] == user.official_title
                send_message += "#{txt[count][2]}\r\n"
                count += 1
              end
              until txt[count][1] == user.official_title
                set_message += "#{txt[count][2]}\r\n"
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
              while txt[count][1] == user.official_title
                send_message += "#{txt[count][2]}\r\n"
                count += 1
              end
              until txt[count][1] == user.official_title
                set_message += "#{txt[count][2]}\r\n"
                count += 1
              end
            end
            message = {
              type: "text",
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
            client.reply_message(event["replyToken"], message)
          end
        when Line::Bot::Event::MessageType::File
          unless /とのトーク.txt/ === event["message"]["fileName"]
            message = {
              type: "text",
              text: "指定のファイルと異なります"
            }
            return client.reply_message(event["replyToken"], message)
          end
          response = client.get_message_content(event.message["id"])
          case response
          when Net::HTTPSuccess
            txt = []
            response.body.each_line do |line|
              txt << line.force_encoding("utf-8")
            end
            p txt
            txt.map { |n| n.gsub!(/\r\n/) { '' } }
            txt[0] = txt[0].delete("[LINE] ")
            txt[0] = txt[0].delete("とのトーク履歴")
            txt.each do |s|
              if s == ""
                txt.delete(s)
              elsif /保存日時：20[0-9][0-9]\/[01][0-2]\/[0-3][0-9] [0-2][0-9]:[0-5][0-9]/ === s
                txt.delete(s)
              end
            end
            p txt
            count = 0
            txt.each do |s|
              if /[0-2][0-9]:[0-5][0-9]/ === s
                txt[count].gsub!(/\"/) { '' }
                txt[count] = s.split(/\t/)
              elsif /\"/ === s
                previous = count - 1
                txt[count].gsub!(/\"/) { '' }
                txt[count] = [txt[previous][0], txt[previous][1], txt[count]]
              end
              count += 1
            end
            p txt
            user = User.find_by!(user_id: event["source"]["userId"])
            user.official_title = txt[0]
            count = 2
            user.resending_point = count
            if txt[count][1] == user.official_title
              while txt[count][1] == user.official_title
                send_message += "#{txt[count][2]}\r\n"
                count += 1
              end
              until txt[count][1] == user.official_title
                set_message += "#{txt[count][2]}\r\n"
                count += 1
              end
            else
              send_message = "スタート"
              until txt[count][1] == user.official_title
                set_message += "#{txt[count][2]}\r\n"
                count += 1
              end
            end
            user.replay_point = count
            user.file_id = event.message["id"]
            user.save!
            message = {
              type: "text",
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
            client.reply_message(event["replyToken"], message)
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
