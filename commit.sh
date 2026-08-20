rm -rf public/ resources/ && hugo --gc --minify
sleep 0.2
git add .
git commit -m $1
git push
