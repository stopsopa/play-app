# Project Instructions

<VERY IMPORTANT>

- By default stick to grug skill unless asked otherwise @./.gemini/skills/grug/SKILL.md
- don't run any cli commands. If you need it then ask me to run them.
- Don't generate summary at the end - just do what asked and just report "done". You might list relative paths (relative to project root) to files changed/deleted/created.
- keep things as simple as possible if it comes to html and css. preferably use raw html and raw css.
- use tokens sparingly do stuff in one go
- never run any commands yourself. If needed just ask. I will run it and provide you with the result

</VERY IMPORTANT>

<general code logic>
avoid negated conditions where else is present:

```

if ( ! condition) {
    ... something else 1  
}
else {
    ... something else 2
}

```

when else is present just remove NOT and swap blocks

```

if ( condition) {
    ... something else 2 
}
else {
    ... something else 1
}

```

</general code logic>

<typical coding errors AI do>

```

src/components/Popover.tsx:23:8 - error TS6133: 'React' is declared but its value is never read.

23 import React, { useEffect, useRef, type ReactNode, type CSSProperties } from "react";
          ~~~~~

src/sandbox/Popover.tsx:1:8 - error TS6133: 'React' is declared but its value is never read.

1 import React, { useState } from "react";

```

prevent these types of errors

</typical coding errors AI do>

<typescript>
When checking typescript validity use:

```
node node_modules/.bin/tsc
```

</typescript>

<run-script>

To run typescript script use

```
/bin/bash ts.sh [<script>] [<args>]
```

instead of:

```
npx tsx [<script>] [<args>]
```

ts.sh takes care of handling PFX="PROJECT1,PROJECT2" via

```
await iteratePrefixes(async function ({ prefix, sql }) { ... });
```

so ideally you want to run scripts:

```
PFX="PROJECT1" /bin/bash ts.sh [<script>] [<args>]
```

for node.js built-in tests use:

```
NO_COVERAGE=true PFX="PROJECT1" /bin/bash ts.sh --test [<script>] [<args>]
```

this way iteratePrefixes will just run once for single connection, not for two when PFX won't be specified and will default to PFX="PROJECT1,PROJECT2" from .env

</run-script>

<bash>
when working with bash follow skill 'bash-scripting' skill

</bash>

<existing code comments>
IMPORTANT:
IMPORTANT:
IMPORTANT:
When you working with existing code and there are comments around functions and generally comment explaining what is happening then leave them all in place.
The same for comments demonstrating how to use given library or script. Those have to say.
Can be only extended. Like new examples added to the comment. That is desirable if covers new cases/ new arguments or new functionalities. Everywhere where logic can be modified by external aruguments or by different ways of callins script and so on.

Also above avery new function and even moderately important functionality block or separate unit of logic it is desirable to also have new comments describing the intention and purpose of that function or functionality.

if just one line of comment is needed then use singe line comments (like with two slashes in js).
But if more than one then use comment type (/\*_ ... _/).
IMPORTANT:
IMPORTANT:
IMPORTANT:
</existing code comments>

<css>
In this project we cant use scss. We have to use only css.

Always use just css. Use nesting in css since modern browsers support it,  like

```
.my_box {
    background: red;

    .my_inner_box {
        ...
    }
}

```

Ideally also try to introduce style next to the components and import in that component like

Test.tsx
Test.css

and do 

import './Test.css'

in Test.tsx

Try to keep styles local to the component as much as possible.

if you need though some universal styles which makes sense to reuse then put it into src/index.css
</css>

<end to end testing>
When building end to end tests make sure that all elements we interact with have data-id attribute (If we can help it - if given code is in control of this project) and use that to to find elements. This way modifying ui I have clear picture where I should be careful when modifying layout because of given data-id is important for some tests.
</end to end testing>

