<div class="jumbotron">
    <div class="container">
        <h1>選挙の結果を大発表！</h1>
    </div>
</div>
<div class="container">
    <h2>個人の部</h2>
    <div id="people" class="row">
        <?php
        $i = 0;
        foreach ($candidates as $candidate) { ?>
            <div class="col-md-3">
                <div class="panel panel-default">
                    <div class="panel-heading">
                        <p><?= (($i < 10) ? $i + 1 : '最下位') ?>. <a
                                    href="/candidates/<?= $candidate['id'] ?>"><?= $candidate['name'] ?></a></p>
                    </div>
                    <div class="panel-body">
                        <p>得票数: <?= $candidate['count'] ?: 0 ?></p>
                        <p>政党: <?= $candidate['political_party'] ?></p>
                    </div>
                </div>
            </div>
            <?php $i++;
        } ?>
    </div>
    <h2>政党の部</h2>
    <div id="parties" class="row">
        <?php
        arsort($parties);
        $i = 0;
        foreach ($parties as $party_name => $party_votes) {
            $i++;
            ?>
            <div class="col-md-3">
                <div class="panel panel-default">
                    <div class="panel-heading">
                        <p><?= $i ?>. <a href="/political_parties/<?= $party_name ?>"><?= $party_name ?></a></p>
                    </div>
                    <div class="panel-body">
                        <p>得票数: <?= $party_votes ?: 0 ?></p>
                    </div>
                </div>
            </div>
        <?php } ?>
    </div>
    <h2>男女比率</h2>
    <div id="sex_ratio" class="row">
        <div class="col-md-6">
            <div class="panel panel-default">
                <div class="panel-heading">
                    <p>男性</p>
                </div>
                <div class="panel-body">
                    <p>得票数: <?= $sex_ratio['男'] ?></p>
                </div>
            </div>
        </div>
        <div class="col-md-6">
            <div class="panel panel-default">
                <div class="panel-heading">
                    <p>女性</p>
                </div>
                <div class="panel-body">
                    <p>得票数: <?= $sex_ratio['女'] ?></p>
                </div>
            </div>
        </div>
    </div>
</div>
