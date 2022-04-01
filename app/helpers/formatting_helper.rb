# frozen_string_literal: true

module FormattingHelper
  def html_aware_format(text, content_type, local, options = {})
    case content_type
    when 'text/markdown'
      HtmlAwareFormatter.new(text, local, options).to_markdown_s
    else # when 'text/plain'
      HtmlAwareFormatter.new(text, local, options).to_s
    end
  end

  def linkify(text, options = {})
    TextFormatter.new(text, options).to_s
  end

  def extract_status_plain_text(status)
    PlainTextFormatter.new(status.text, status.local?).to_s
  end
  module_function :extract_status_plain_text

  def status_content_format(status)
    html_aware_format(status.text, status.content_type, status.local?, preloaded_accounts: [status.account] + (status.respond_to?(:active_mentions) ? status.active_mentions.map(&:account) : []))
  end

  def quote_status_content_format(status)
    url = ActivityPub::TagManager.instance.url_for(status.quote)
    link = linkify(url)
    html = html_aware_format(status.text, status.content_type, status.local?, preloaded_accounts: [status.account] + (status.respond_to?(:active_mentions) ? status.active_mentions.map(&:account) : []))
    html.sub(/(<[^>]+>)\z/, "<span class=\"quote-inline\"><br/>QT: #{link}</span>\\1")
    return html
  end

  def account_bio_format(account)
    html_aware_format(account.note, default_content_type, account.local?)
  end

  def account_field_value_format(field, with_rel_me: true)
    html_aware_format(field.value, default_content_type, field.account.local?, with_rel_me: with_rel_me, with_domains: true, multiline: false)
  end

  private

  def default_content_type
    'text/plain'
  end
end
