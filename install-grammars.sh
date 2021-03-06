#!/bin/bash -ex

JQ=$(which jq || true)
if [ -z "$JQ" ] ; then
    echo "Requires jq https://github.com/stedolan/jq/wiki/Installation"
    exit -1
fi

TS=$(which tree-sitter || true)
if [ -z "$TS" ] || [[ ! $($TS --version) =~ "0.20.0-alpha" ]] ; then
    echo "Requires tree-sitter cli version 0.20.0-alpha"
    exit -1
fi

function git_refresh {
    local repo
    local url
    local branch
    repo=$1
    url=$2
    if [ -d "$repo" ] ; then
	pushd $repo
	branch=$(git rev-parse --abbrev-ref HEAD)
	git fetch -q -u origin $branch:$branch --depth=1
	popd
    else
	git clone --depth=1 --single-branch $url $repo
    fi
}

DIR=$(git rev-parse --show-toplevel)/grammars
mkdir -p $DIR
declare -a official=()
IFS=$'\n'
for url in $(egrep -o "https://github.com/tree-sitter/tree-sitter-[A-Za-z0-9-]+" \
		   docs/index.md | sort -u) ; do
    unset IFS
    repo=$(basename $url)
    official+=( $repo )
    git_refresh "$DIR/$repo" $url
done

IFS=$'\n'
for url in $(egrep -o "https://github.com/.+/tree-sitter-[A-Za-z0-9-]+" \
		   docs/index.md | sort -u) ; do
    unset IFS
    repo=$(basename $url)
    if [[ ! " ${official[*]} " =~ " ${repo} " ]] ; then
	git_refresh "$DIR/$repo" $url
    fi
done

cat <<EOF > "$DIR/config.json"
{
  "parser-directories": [
    "$DIR"
  ]
}
EOF

QDIR="$(tree-sitter dump-libpath)"/../queries
mkdir -p "$QDIR"
for repo in "$DIR"/tree-sitter-* ; do
    scope=$(cat $repo/package.json | 2>/dev/null jq -r '."tree-sitter"[].scope')
    if [ ! -z "$scope" ] ; then
	if TREE_SITTER_DIR="$DIR" 1>/dev/null 2>/dev/null \
			  tree-sitter parse --scope "$scope" /dev/null ; then
	    if [ -f "$repo/queries/highlights.scm" ] ; then
		LANG=${repo##*-}
		mkdir -p "$QDIR/$LANG"
		cp -p "$repo/queries/highlights.scm" "$QDIR/$LANG"
	    fi
	fi
    fi
done
