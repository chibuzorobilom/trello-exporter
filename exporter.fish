if [ (count $argv) -lt 3 ]
  echo "please call this script with <board-id> <trello-api-key> <trello-token> as arguments"
  echo "to generate an API key and a token, visit https://trello.com/app-key"
  exit
end

set boardId $argv[1]
set key $argv[2]
set token $argv[3]

function get --description "get <path> pairs..."
  set path $argv[1]
  set params "token=$token&key=$key"
  for i in (seq 2 (count $argv))
    if [ (math $i%2) = 0 ]
      set k $argv[(math $i)]
      set v $argv[(math $i+1)]
      set params "$params&$k=$v"
    end
  end
  sleep 0.2
  curl -s "https://api.trello.com$path?$params"
end

function parsedate --description "parsedate <trello-entity-id>"
  set id $argv[1]
  set hex (expr substr $id 1 8)
  set dec (perl -le "print hex('$hex');")
  date -d @$dec +'%Y-%m-%d %H:%M:%S'
end

rm -rf trello_exported_data
mkdir -p trello_exported_data
cd trello_exported_data
mkdir -p _archived

set lists (get "/1/boards/$boardId/lists" filter all fields name,open)
for i in (seq 0 (math (echo $lists | jq '. | length') - 1))
  set boarddir (pwd)

  set name (echo $lists | jq -r ".[$i].name" | perl -X -i -pe's/\// /g')
  set id (echo $lists | jq -r ".[$i].id")

  set open (echo $lists | jq -r ".[$i].open")
  if [ open = 'closed' ]
    cd _archived
  end

  if [ -d $name ]
    set listdir "$name-$id"
  else
    set listdir $name
  end
  mkdir $listdir
  cd $listdir
  set listdir (pwd)

  # cards
  mkdir -p _archived
  set cards (get "/1/lists/$id/cards" attachments 'true' attachment_fields name,url members 'true' member_fields username checkItemstates 'true' checklists all filter all fields closed,desc,due,labels,name,shortLink)
  for i in (seq 0 (math (echo $cards | jq '. | length') - 1))
    set card (echo $cards | jq -r ".[$i]")

    set name (echo $card | jq -r ".name" | perl -X -i -pe's/\// /g')
    set id (echo $card | jq -r ".id")
    
    set open (echo $card | jq -r ".open")
    if [ open = 'closed' ]
      cd _archived
    end
    
    if [ -d $name ]
      set cardfile "$name-$id.md"
    else
      set cardfile "$name.md"
    end

    # actually write the file
    echo '---' > $cardfile
    echo (echo $card | jq -r '"name: \(.name)"') >> $cardfile
    echo 'created:' (parsedate $id) >> $cardfile
    echo $card | jq -r '"id: \(.id)"' >> $cardfile
    echo $card | jq -r '"url: https://trello.com/c/\(.shortLink)"' >> $cardfile
    if [ (echo $card | jq '.due') != null ]
      echo -e (echo $card | jq -r '"due: \(.due)"') >> $cardfile
    end
    # labels
    if [ (echo $card | jq '.labels | length') != '0' ]
      echo -e 'labels:' >> $cardfile
      for l in (seq 0 (math (echo $card | jq '.labels | length') - 1))
        set label (echo $card | jq ".labels[$l]")
        echo -e (echo $label | jq -r '" - \(.name)"') >> $cardfile
      end
    end
    # members
    if [ (echo $card | jq '.members | length') != '0' ]
      echo -e 'members:' >> $cardfile
      for m in (seq 0 (math (echo $card | jq '.members | length') - 1))
        set member (echo $card | jq ".members[$m]")
        echo -e (echo $member | jq -r '" - \(.username)"') >> $cardfile
      end
    end
    echo '---' >> $cardfile
    echo '' >> $cardfile
    # description
    set desc (echo $card | jq '.desc')
    set desclen (expr length $desc)
    if [ $desclen != '2' ]
      set desc (expr substr $desc 2 (math $desclen-2))
      echo -e $desc >> $cardfile
      echo '' >> $cardfile
    end
    # attachments
    if [ (echo $card | jq '.attachments | length') != '0' ]
      echo '---' >> $cardfile
      echo '' >> $cardfile
      echo 'ATTACHMENTS' >> $cardfile
      echo '-----------' >> $cardfile
      echo '' >> $cardfile
      for a in (seq 0 (math (echo $card | jq '.attachments | length') - 1))
        set attachment (echo $card | jq ".attachments[$a]")
        echo -e (echo $attachment | jq -r '"- \(.name): \(.url)"') >> $cardfile
      end
      echo '' >> $cardfile
    end
    # checklists
    if [ (echo $card | jq '.checklists | length') != '0' ]
      echo '---' >> $cardfile
      echo '' >> $cardfile
      echo 'CHECKLISTS' >> $cardfile
      echo '----------' >> $cardfile
      echo '' >> $cardfile
      for cl in (seq 0 (math (echo $card | jq '.checklists | length') - 1))
        set checklist (echo $card | jq ".checklists[$cl]")
        echo -e (echo $checklist | jq -r '"- \(.name)"') >> $cardfile
        for ci in (seq 0 (math (echo $checklist | jq '.checkItems | length') - 1))
          set checkitem (echo $checklist | jq ".checkItems[$ci]")
          if [ (echo $checkitem | jq -r '.state') = 'complete' ]
            echo -e (echo $checkitem | jq -r '"  - [x] \(.name)"') >> $cardfile
          else
            echo -e (echo $checkitem | jq -r '"  - [ ] \(.name)"') >> $cardfile
          end
        end
      end
      echo '' >> $cardfile
    end

    # comments
    set comments (get "/1/cards/$id/actions" filter commentCard fields data limit '1000' member 'false' memberCreator 'true' memberCreator_fields username)
    if [ (echo $comments | jq '. | length') != '0' ]
      echo '---' >> $cardfile
      echo '' >> $cardfile
      echo 'COMMENTS' >> $cardfile 
      echo '========' >> $cardfile
      echo '' >> $cardfile
      for c in (seq 0 (math (echo $comments | jq '. | length') - 1))
        set text (echo $comments | jq ".[$c].data.text")
        set id (echo $comments | jq -r ".[$c].id")
        set username (echo $comments | jq -r ".[$c].memberCreator.username")
        echo $comment | jq .
        echo $username 'at' (parsedate $id)':' >> $cardfile
        echo '' >> $cardfile
        set textlen (expr length $text)
        set text (expr substr $text 2 (math $textlen-2))
        echo -e '  '$text | perl -X -i -pe's/\n/\n  /g' >> $cardfile
        echo '' >> $cardfile
      end
    end

    cd $listdir
  end

  cd $boarddir
end

cd ..
tree -L 3 trello_exported_data
