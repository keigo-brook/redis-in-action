# -*- coding: utf-8 -*-
ONE_WEEK_IN_SECONDS = 7 * 86400
VOTE_SCORE = 432
ARTICLES_PER_PAGE = 25

def article_vote(conn, user, article)
  # 投票できる記事の投稿時刻を計算する
  cutoff = Time.now.to_i - ONE_WEEK_IN_SECONDS

  # 記事がまだ投稿できる状態かどうかをチェックする
  return if conn.zscore('time:', article) < cutoff

  # article:id からidを取り出す
  article_id = article.split(':')[-1]

  # ユーザーがこの記事にまだ投票していなければ,記事のスコアと投票数をインクリメントする
  if conn.sadd('voted:' + article_id, user)
    conn.zincrby('score:', VOTE_SCORE, article)
    conn.hincrby(article, 'votes', 1)
  end
end

def post_article(conn, user, title, link)
  # 新しい記事IDを生成する
  article_id = conn.incr('article:')

  voted = "voted:#{article_id}"
  # 投稿者はその記事に投票したものとしてスタートする
  conn.sadd(voted, user)
  # 一週間後に記事投票情報は自動的に削除されるように設定する
  conn.expire(voted, ONE_WEEK_IN_SECONDS)

  now = Time.now.to_i
  article = "article:#{article_id}"
  # article HASHを作る
  conn.mapped_hmset(
    article,
    {
      title: title,
      link: link,
      poster: user,
      time: now,
      votes: 1
    }
  )

  # 投票時刻順とスコア順の２つのZSETに記事を追加する
  conn.zadd('score:', now + VOTE_SCORE, article)
  conn.zadd('time:', now, article)

  article_id
end

def get_articles(conn, page, order = 'score:')
  # 記事をフェッチするために，先頭と末尾のインデックスをセットアップする
  start = (page - 1) * ARTICLES_PER_PAGE
  stop = start + ARTICLES_PER_PAGE - 1
  # 記事IDをフェッチする（デフォルトではスコアの逆順）
  ids = conn.zrevrange(order, start, stop)

  articles = []
  ids.each do |id|
    # 記事IDをのリストから記事情報を取得する
    article_data = conn.hgetall(id)
    article_data[:id] = id
    articles.push(article_data)
  end
  # ids.inject([]) do |articles, id|
  #   articles << conn.hgetall(id).merge(id: id)
  # end
  articles
end

def add_remove_groups(conn, article_id, to_add = [], to_remove = [])
  # post_articleのときと同じように記事情報を作る
  article = "article:#{article_id}"

  to_add.each do |group|
    # 記事を追加すべきグループに追加する
    conn.sadd("group:#{group}", article)
  end

  to_remove.each do |group|
    # 記事を削除すべきグループから削除する
    conn.srem("group:#{group}", article)
  end
end

def get_group_articles(conn, group, page, order = 'score:')
  # グループごと,ソート順ごとにキーを作る
  key = order + group

  # 最近キーをソートしていなければ,ソートすべき
  unless conn.exists(key)
    # グループ内の記事は,スコアまたは投稿時刻順にソートされる
    conn.zinterstore(key, ["group:#{group}", order], aggregate: 'max')
    # ZSETが60秒で自動的に削除されるようにする
    conn.expire(key, 60)
  end

  # get_articles関数を呼び出して,ページ分割と記事データの読み出しを処理する
  get_articles(conn, page, key)
end
