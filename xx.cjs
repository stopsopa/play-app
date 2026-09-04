// to install go to: https://stopsopa.github.io//pages/bash/index.html#xx

// viewer       : https://stopsopa.github.io/viewer.html?file=%2Fpages%2Fbash%2Fxx%2Fxx-template.cjs
// github edit  : https://github.com/stopsopa/stopsopa.github.io/blob/master/pages/bash/xx/xx-template.cjs

// in order to run any xx command with custom export env var:
// (shopt -s expand_aliases; export ENVFILE=.env.ci; xx "docker up")

// 🚀 -
// ✅ -
// ⚙️  -
// 🗑️  -
// 🛑 -
// to call other xx commands from inside any xx command use:
//    shopt -s expand_aliases && source ~/.bashrc
// after that just do:
//   xx <command_name>
const S = "\\";
const GRAY = "\x1b[38;5;244m",
  BLACK = "\x1b[30m",
  RED = "\x1b[31m",
  GREEN = "\x1b[32m",
  YELLOW = "\x1b[33m",
  BLUE = "\x1b[34m",
  MAGENTA = "\x1b[35m",
  CYAN = "\x1b[36m",
  WHITE = "\x1b[37m",
  BOLD = "\x1b[1m",
  REVERSE = "\x1b[7m",
  RESET = "\x1b[0m";

const enter = `printf '\n${GREEN}Press Enter to continue (any other key exits)...${RESET}\n';old=$(stty -g);stty -icanon -echo
IFS= read -r -n1 k 2>/dev/null||IFS= read -r k;stty "$old"
[ -n "$k" ]&&exit 0;`;

const esc = `printf '\n${GREEN}Press any key to continue (Esc to exit)...${RESET}\n';old=$(stty -g);stty -icanon -echo
IFS= read -r -n1 k 2>/dev/null||IFS= read -r k;stty "$old"
[ "$k" = "$(printf '\\033')" ]&&exit 0;`;

module.exports = (setup) => {
  return {
    help: {
      command: `
set -e  
        
cat <<EEE

  🐙 GitHub: $(git ls-remote --get-url origin | awk '{\$1=\$1};1' | tr -d '\\n' | sed -E 's/git@github\\.com:([^/]+)\\/(.+)\\.git/https:\\/\\/github.com\\/\\1\\/\\2/g')

EEE

      `,
      description: "Status of all things",
      source: false,
      confirm: false,
    },
    [`provision.check`]: {
      command: `
cat <<EEE

/bin/bash check.provision.sh

EEE

echo -e "\n      Press enter to continue\n"
read

/bin/bash check.provision.sh
`,
      description: `Check provisioning profile expiration`,
      confirm: false,
    },
    [`provision.new`]: {
      command: `
cat <<EEE

/bin/bash refresh-provisioning-profile.sh

The trick is to turn off the xcode IDE
and then remove provisioning file which is usually somewhere
~ szdz √ ls -la ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/94759b3d-9252-4052-bdc1-9567072b22b3.mobileprovision
-rw-r--r--  1 szdz  staff  12463  4 Sep 01:03 /Users/szdz/Library/Developer/Xcode/UserData/Provisioning Profiles/94759b3d-9252-4052-bdc1-9567072b22b3.mobileprovision
~ szdz √

EEE

echo -e "\n      Press enter to continue\n"
read

/bin/bash refresh-provisioning-profile.sh 
`,
      description: `Refresh the Xcode development provisioning profile.`,
      confirm: false,
    },

    ...setup,
  };
};
