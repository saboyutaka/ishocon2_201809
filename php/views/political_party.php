<div class="jumbotron">
    <div class="container">
        <h1><?= $political_party ?></h1>
    </div>
</div>
<div class="container">
    <div class="row">
        <div id="info" class="jumbotron">
            <h2>得票数</h2>
            <p id="votes"><?= $votes ?></p>
            <h2>候補者</h2>
            <ul id="members">
                <?php foreach ($candidates as $candidate) { ?>
                    <li><?= $candidate['name'] ?></li>
                <?php } ?>
            </ul>
            <h2>支持者の声</h2>
            <ul id="voices">
                <?php foreach ($keywords as $keyword) { ?>
                    <li><?= $keyword ?></li>
                <?php } ?>
            </ul>
        </div>
    </div>
</div>
