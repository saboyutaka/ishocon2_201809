import datetime
import html
import os
import pathlib
import urllib

import MySQLdb.cursors

from flask import Flask, abort, redirect, render_template, request, session

static_folder = pathlib.Path(__file__).resolve().parent / 'public'
app = Flask(__name__, static_folder=str(static_folder), static_url_path='')

app.secret_key = os.environ.get('ISHOCON2_SESSION_SECRET', 'showwin_happy')

_config = {
    'db_host': os.environ.get('ISHOCON2_DB_HOST', 'localhost'),
    'db_port': int(os.environ.get('ISHOCON2_DB_PORT', '3306')),
    'db_username': os.environ.get('ISHOCON2_DB_USER', 'ishocon'),
    'db_password': os.environ.get('ISHOCON2_DB_PASSWORD', 'ishocon'),
    'db_database': os.environ.get('ISHOCON2_DB_NAME', 'ishocon2'),
}


def config(key):
    if key in _config:
        return _config[key]
    else:
        raise "config value of %s undefined" % key


def db():
    if hasattr(request, 'db'):
        return request.db
    else:
        request.db = MySQLdb.connect(**{
            'host': config('db_host'),
            'port': config('db_port'),
            'user': config('db_username'),
            'passwd': config('db_password'),
            'db': config('db_database'),
            'charset': 'utf8mb4',
            'cursorclass': MySQLdb.cursors.DictCursor,
            'autocommit': True,
        })
        cur = request.db.cursor()
        cur.execute("SET SESSION sql_mode='TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY'")
        cur.execute('SET NAMES utf8mb4')
        return request.db


def get_election_results():
    cur = db().cursor()
    cur.execute("""
SELECT c.id, c.name, c.political_party, c.sex, v.count
FROM candidates AS c
LEFT OUTER JOIN
  (SELECT candidate_id, COUNT(*) AS count
  FROM votes
  GROUP BY candidate_id) AS v
ON c.id = v.candidate_id
ORDER BY v.count DESC
""")
    return cur.fetchall()


def get_voice_of_supporter(candidate_ids):
    cur = db().cursor()
    candidate_ids_str = ','.join([str(cid) for cid in candidate_ids])
    cur.execute("""
SELECT keyword
FROM votes
WHERE candidate_id IN ({})
GROUP BY keyword
ORDER BY COUNT(*) DESC
LIMIT 10
""".format(candidate_ids_str))
    records = cur.fetchall()
    return [r['keyword'] for r in records]


def get_all_party_name():
    cur = db().cursor()
    cur.execute('SELECT political_party FROM candidates GROUP BY political_party')
    records = cur.fetchall()
    return [r['political_party'] for r in records]


def get_candidate_by_id(candidate_id):
    cur = db().cursor()
    cur.execute('SELECT * FROM candidates WHERE id = {}'.format(candidate_id))
    return cur.fetchone()


def db_initialize():
    cur = db().cursor()
    cur.execute('DELETE FROM votes')


@app.teardown_request
def close_db(exception=None):
    if hasattr(request, 'db'):
        request.db.close()


@app.route('/')
def get_index():
    candidates = []
    election_results = get_election_results()
    # 上位10人と最下位のみ表示
    candidates += election_results[:10]
    candidates.append(election_results[-1])

    parties_name = get_all_party_name()
    parties = {}
    for name in parties_name:
        parties[name] = 0
    for r in election_results:
        parties[r['political_party']] += r['count'] or 0
    parties = sorted(parties.items(), key=lambda x: x[1], reverse=True)

    sex_ratio = {'men': 0, 'women': 0}
    for r in election_results:
        if r['sex'] == '男':
            sex_ratio['men'] += r['count'] or 0
        elif r['sex'] == '女':
            sex_ratio['women'] += r['count'] or 0

    return render_template('index.html',
                           candidates=candidates,
                           parties=parties,
                           sex_ratio=sex_ratio)


@app.route('/candidates/<int:candidate_id>')
def get_candidate(candidate_id):
    cur = db().cursor()
    cur.execute('SELECT * FROM candidates WHERE id = {}'.format(candidate_id))
    candidate = cur.fetchone()
    if not candidate:
        return redirect('/')

    cur.execute('SELECT COUNT(*) AS count FROM votes WHERE candidate_id = {}'.format(candidate_id))
    votes = cur.fetchone()['count']
    keywords = get_voice_of_supporter([candidate_id])
    return render_template('candidate.html',
                           candidate=candidate,
                           votes=votes,
                           keywords=keywords)


@app.route('/political_parties/<string:name>')
def get_political_party(name):
    cur = db().cursor()
    votes = 0
    for r in get_election_results():
        if r['political_party'] == name:
            votes += r['count'] or 0

    cur.execute('SELECT * FROM candidates WHERE political_party = "{}"'.format(name))
    candidates = cur.fetchall()
    candidate_ids = [c['id'] for c in candidates]
    keywords = get_voice_of_supporter(candidate_ids)
    return render_template('political_party.html',
                           political_party=name,
                           votes=votes,
                           candidates=candidates,
                           keywords=keywords)


@app.route('/vote')
def get_vote():
    cur = db().cursor()
    cur.execute('SELECT * FROM candidates')
    candidates = cur.fetchall()
    return render_template('vote.html',
                           candidates=candidates,
                           message='')


@app.route('/vote', methods=['POST'])
def post_vote():
    cur = db().cursor()
    cur.execute('SELECT * FROM users WHERE name = "{}" AND address = "{}" AND mynumber = "{}"'.format(
        request.form['name'], request.form['address'], request.form['mynumber']
    ))
    user = cur.fetchone()
    cur.execute('SELECT * FROM candidates WHERE name = "{}"'.format(request.form['candidate']))
    candidate = cur.fetchone()
    voted_count = 0
    if user:
        cur.execute('SELECT COUNT(*) AS count FROM votes WHERE user_id = {}'.format(user['id']))
        voted_count = cur.fetchone()['count']

    cur.execute('SELECT * FROM candidates')
    candidates = cur.fetchall()
    if not user:
        return render_template('vote.html', candidates=candidates, message='個人情報に誤りがあります')
    elif user['votes'] < (int(request.form['vote_count']) + voted_count):
        return render_template('vote.html', candidates=candidates, message='投票数が上限を超えています')
    elif not request.form['candidate']:
        return render_template('vote.html', candidates=candidates, message='候補者を記入してください')
    elif not candidate:
        return render_template('vote.html', candidates=candidates, message='候補者を正しく記入してください')
    elif not request.form['keyword']:
        return render_template('vote.html', candidates=candidates, message='投票理由を記入してください')

    for _ in range(int(request.form['vote_count'])):
        cur.execute('INSERT INTO votes (user_id, candidate_id, keyword) VALUES ({}, {}, "{}")'.format(
            user['id'], candidate['id'], request.form['keyword']
        ))
    return render_template('vote.html', candidates=candidates, message='投票に成功しました')


@app.route('/initialize')
def get_initialize():
    db_initialize()


if __name__ == "__main__":
    app.run()
