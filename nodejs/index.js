const util = require('util');

const express = require('express');
const bodyParser = require('body-parser')

const app = express();

app.set('views', __dirname + '/views');
app.set('view engine', 'ejs');
app.use(express.static('public'));
app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());

const mysql = require('mysql');
const pool = mysql.createPool({
    connectionLimit: 20,
    host: process.env.ISHOCON2_DB_HOST || 'localhost',
    port: process.env.ISHOCON2_DB_PORT || 3306,
    user: process.env.ISHOCON2_DB_USER || 'ishocon',
    password: process.env.ISHOCON2_DB_PASSWORD || 'ishocon',
    database: process.env.ISHOCON2_DB_NAME || 'ishocon2'
});
pool.query = util.promisify(pool.query, pool);

const electionResults = () => {
    return pool.query(`
SELECT c.id, c.name, c.political_party, c.sex, v.count
FROM candidates AS c
LEFT OUTER JOIN
    (SELECT candidate_id, COUNT(*) AS count
    FROM votes
    GROUP BY candidate_id) AS v
ON c.id = v.candidate_id
ORDER BY v.count DESC
    `);
}

const voiceOfSupporter = (candidateIds) => {
    return pool.query(`
SELECT keyword
FROM votes
WHERE candidate_id IN (?)
GROUP BY keyword
ORDER BY COUNT(*) DESC
LIMIT 10
    `, [candidateIds]).then((rows) => {
            return rows.map((a) => {
                return a['keyword'];
            })
        });
}

app.get('/test', (_, res) => {
    electionResults().then((r) => res.json(r));
});

app.get('/', (_, res) => {
    let p = Promise.resolve()

    candidates = []
    p = p.then(() => electionResults()
        .then((rows) => {
            // 上位10人と最下位のみ表示
            candidates = rows.filter((_, i) => i < 10 || 28 < i);
        }));

    parties = {}
    p = p.then(() =>
        pool.query(
            `SELECT political_party FROM candidates GROUP BY political_party`)
            .then((rows) =>
                rows.forEach((a) => {
                    parties[a['political_party']] = 0;
                })
            )
    );

    p = p.then(() =>
        electionResults().then((rows) => {
            rows.forEach((r) => {
                parties[r['political_party']] += r['count'] || 0;
            });
        }));

    sexRatio = { '男': 0, '女': 0 };
    p = p.then(() =>
        electionResults().then((rows) => {
            rows.forEach((r) => {
                sexRatio[r['sex']] += r['count'] || 0;
            });
        }));

    p.then(() => {
        res.render('layout', {
            file: 'index',
            content: {
                candidates: candidates,
                parties: parties,
                sexRatio: sexRatio,
            }
        });
    });
});

app.get('/candidates/:id', (req, res) => {
    let p = Promise.resolve();

    let candidate = {};
    p = p.then(() => pool.query('SELECT * FROM candidates WHERE id = ?', req.params.id)
        .then((candidates) => {
            if (candidates.length === 0) res.redirect('/');
            candidate = candidates[0];
        }));

    let votes = 0;
    p = p.then(() => pool.query('SELECT COUNT(*) AS count FROM votes WHERE candidate_id = ?', req.params.id)
        .then(([row]) => {
            votes = row['count'];
        }));

    let keywords
    p = p.then(() => voiceOfSupporter(req.params.id)
        .then((rows) => {
            keywords = rows;
        }));

    p.then(() => {
        res.render('layout', {
            file: 'candidate',
            content: {
                candidate: candidate,
                votes: votes,
                keywords: keywords,
            }
        });
    });
});

app.get('/political_parties/:name', (req, res) => {
    let p = Promise.resolve();

    let votes = 0
    p = p.then(() => electionResults().then((rows) => {
        rows.forEach((r) => {
            if (r['political_party'] == req.params.name) {
                votes += r['count'];
            }
        })
    }));

    let candidates = {};
    let candidateIds = [];
    let keywords = [];
    p = p.then(() => pool.query('SELECT * FROM candidates WHERE political_party = ?', [req.params.name])
        .then((rows) => {
            candidates = rows;
            candidateIds = rows.map((c) => c['id']);
        }).then(() => {
            voiceOfSupporter(candidateIds).then((rows) => {
                keywords = rows;
            });
        })
    );

    p.then(() => {
        res.render('layout', {
            file: 'political_party',
            content: {
                politicalParty: req.params.name,
                votes: votes,
                candidates: candidates,
                keywords: keywords,
            }
        });
    });
});

app.get('/vote', (_, res) => {
    pool.query('SELECT * FROM candidates').then((candidates) => {
        res.render('layout', {
            file: 'vote',
            content: {
                candidates: candidates,
                message: '',
            }
        });
    });
});

app.post('/vote', (req, res) => {
    let p = Promise.resolve();

    let user = {};
    let votedCount = 0
    p = p.then(() => pool.query('SELECT * FROM users WHERE name = ? AND address = ? AND mynumber = ?',
        [
            req.body.name,
            req.body.address,
            req.body.mynumber,
        ]
    ).then((rows) => {
        user = rows[0];
    }).then(() => {
        if (user != null) {
            return pool.query('SELECT COUNT(*) AS count FROM votes WHERE user_id = ?', user['id'])
                .then(([row]) => {
                    votedCount = row['count']
                });
        }
    }));

    let candidate = {};
    p = p.then(() => pool.query('SELECT * FROM candidates WHERE name = ?', [
        req.body.candidate
    ]).then((rows) => {
        candidate = rows[0];
    }));

    let candidates = {};
    p = p.then(() => pool.query('SELECT * FROM candidates').then((rows) => {
        candidates = rows;
    }));

    p.then(() => {
        if (user == null) {
            return { candidates: candidates, message: '個人情報に誤りがあります' };
        } else if (user['votes'] < parseInt(req.body.vote_count, 10) + votedCount) {
            return { candidates: candidates, message: '投票数が上限を超えています' };
        } else if (req.body.candidate == null || req.body.candidate == '') {
            return { candidates: candidates, message: '候補者を記入してください' };
        } else if (candidate == null) {
            return { candidates: candidates, message: '候補者を正しく記入してください' };
        } else if (req.body.keyword == null || req.body.keyword == '') {
            return { candidates: candidates, message: '投票理由を記入してください' }
        }
        for (let i = 0; i < req.body.vote_count; i++) {
            p = p.then(() => pool.query('INSERT INTO votes (user_id, candidate_id, keyword) VALUES (?, ?, ?)',
                [user['id'], candidate['id'], req.body.keyword]));
        }
        return { candidates: candidates, message: '投票に成功しました' }
    }).then((content) => res.render('layout', {
        file: 'vote',
        content: content,
    }));
});

app.get('/initialize', (_, res) => {
    pool.query('DELETE FROM votes').then(() =>
        res.send('Finish'))
})

var server = app.listen(8080, function () {
    var host = server.address().address;
    var port = server.address().port;

    console.log('Example app listening at http://%s:%s', host, port);
});