<?php

require 'vendor/autoload.php';

function getPDO()
{
    $host = getenv('ISHOCON2_DB_HOST') ?: 'localhost';
    $port = getenv('ISHOCON2_DB_PORT') ?: '3306';
    $user = getenv('ISHOCON2_DB_USER') ?: 'ishocon';
    $password = getenv('ISHOCON2_DB_PASSWORD') ?: 'ishocon';
    $dbname = getenv('ISHOCON2_DB_NAME') ?: 'ishocon2';
    $dsn = "mysql:host={$host};port={$port};dbname={$dbname};charset=utf8mb4";
    $pdo = new PDO(
        $dsn,
        $user,
        $password,
        [
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
        ]
    );
    return $pdo;
}

function election_results()
{
    $stmt = getPDO()->query('
SELECT c.id, c.name, c.political_party, c.sex, v.count
FROM candidates AS c
LEFT OUTER JOIN
  (SELECT candidate_id, COUNT(*) AS count
  FROM votes
  GROUP BY candidate_id) AS v
ON c.id = v.candidate_id
ORDER BY v.count DESC');
    return $stmt->fetchAll();
}

function voice_of_supporter($ids)
{
    $stmt = getPDO()->prepare('
SELECT keyword
FROM votes
WHERE candidate_id IN (?' . str_repeat(',?', sizeof($ids) - 1) . ')
GROUP BY keyword
ORDER BY COUNT(*) DESC
LIMIT 10');
    $stmt->execute($ids);
    return array_map(
        function ($a) {
            return $a['keyword'];
        },
        $stmt->fetchAll());
}

function db_initialize()
{
    getPDO()->query('DELETE FROM votes');
}

Flight::route('GET /', function () {
    $candidates = [];
    foreach (election_results() as $i => $r) {
        # 上位10人と最下位のみ表示
        if ($i < 10 || 28 < $i) {
            $candidates[] = $r;
        }
    }

    $parties_set = getPDO()->query('SELECT political_party FROM candidates GROUP BY political_party');
    $parties = [];
    foreach ($parties_set as $a) {
        $parties[$a['political_party']] = 0;
    }
    foreach (election_results() as $r) {
        $parties[$r['political_party']] += $r['count'] ?: 0;
    }

    $sex_ratio = ['男' => 0, '女' => 0];
    foreach (election_results() as $r) {
        $sex_ratio[$r['sex']] += $r['count'] ?: 0;
    }

    Flight::render('index', [
        'candidates' => $candidates,
        'parties' => $parties,
        'sex_ratio' => $sex_ratio
    ], 'content');
    Flight::render('layout');
});

Flight::route('GET /candidates/@id', function ($id) {
    $stmt1 = getPDO()
        ->prepare('SELECT * FROM candidates WHERE id = ?');
    $stmt1->execute([$id]);
    $candidate = $stmt1->fetch();

    if ($candidate === false) {
        Flight::redirect('/');
    } else {
        $stmt2 = getPDO()
            ->prepare('SELECT COUNT(*) AS count FROM votes WHERE candidate_id = ?');
        $stmt2->execute([$id]);
        $votes = $stmt2->fetch()['count'];
        $keywords = voice_of_supporter([$id]);
        Flight::render('candidate', [
            'candidate' => $candidate,
            'votes' => $votes,
            'keywords' => $keywords
        ], 'content');
        Flight::render('layout');
    }
});

Flight::route('GET /political_parties/@name', function ($name) {
    $votes = 0;
    foreach (election_results() as $r) {
        if ($r['political_party'] === $name) {
            $votes += $r['count'] ?: 0;
        }
    }
    $stmt = getPDO()->prepare('SELECT * FROM candidates WHERE political_party = ?');
    $stmt->execute([$name]);
    $candidates = $stmt->fetchAll();
    $candidate_ids = [];
    foreach ($candidates as $c) {
        $candidate_ids[] = $c['id'];
    }
    $keywords = voice_of_supporter($candidate_ids);
    Flight::render('political_party', [
        'political_party' => $name,
        'votes' => $votes,
        'candidates' => $candidates,
        'keywords' => $keywords
    ], 'content');
    Flight::render('layout');
});

Flight::route('GET /vote', function () {
    $candidates = getPDO()->query('SELECT * FROM candidates')->fetchAll();
    Flight::render('vote', [
        'candidates' => $candidates,
        'message' => ''
    ], 'content');
    Flight::render('layout');
});

Flight::route('POST /vote', function () {
    Flight::request()->data;
    $stmt1 = getPDO()->prepare('SELECT * FROM users WHERE name = ? AND address = ? AND mynumber = ?');
    $stmt1->execute([
        Flight::request()->data['name'],
        Flight::request()->data['address'],
        Flight::request()->data['mynumber'],
    ]);
    $user = $stmt1->fetch();
    $stmt2 = getPDO()->prepare('SELECT * FROM candidates WHERE name = ?');
    $stmt2->execute([Flight::request()->data['candidate']]);
    $candidate = $stmt2->fetch();
    $voted_count = 0;
    if ( $user === false) {
        $stmt3 = getPDO()->prepare('SELECT COUNT(*) AS count FROM votes WHERE user_id = ?');
        $stmt3->execute([$user['id']]);
        $voted_count = $stmt3->fetch()['count'];
    }
    $candidates = getPDO()->query('SELECT * FROM candidates')->fetchAll();
    if ( $user === false) {
        Flight::render('vote', [
            'candidates' => $candidates,
            'message' => '個人情報に誤りがあります'
        ], 'content');
    } else if ($user['votes'] < (int)(Flight::request()->data['vote_count']) + $voted_count) {
        Flight::render('vote', [
            'candidates' => $candidates,
            'message' => '投票数が上限を超えています'
        ], 'content');
    } else if (is_null(Flight::request()->data['candidate']) || Flight::request()->data['candidate'] === '') {
        Flight::render('vote', [
            'candidates' => $candidates,
            'message' => '候補者を記入してください'
        ], 'content');
    } else if ( $candidate === false) {
        Flight::render('vote', [
            'candidates' => $candidates,
            'message' => '候補者を正しく記入してください'
        ], 'content');
    } else if (is_null(Flight::request()->data['keyword']) || Flight::request()->data['keyword'] === '') {
        Flight::render('vote', [
            'candidates' => $candidates,
            'message' => '投票理由を記入してください'
        ], 'content');
    } else {
        for ($i = 0; $i < Flight::request()->data['vote_count']; $i++) {
            $stmt4 = getPDO()->prepare('INSERT INTO votes (user_id, candidate_id, keyword) VALUES (?, ?, ?)');
            $stmt4->execute([$user['id'], $candidate['id'], Flight::request()->data['keyword']]);
        }
        Flight::render('vote', [
            'candidates' => $candidates,
            'message' => '投票に成功しました'
        ], 'content');
    }
    Flight::render('layout');
});

Flight::route('GET /initialize', db_initialize);

Flight::start();
