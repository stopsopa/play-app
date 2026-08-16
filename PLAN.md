I'm about to write an app in directory `sanemp3`.

App is written in Swift for iPhone.

App should provide some ways to open any directory from Files,

Then present mp3 files in given directory and allow me to play them one by one. from top to bottom.

But we should also have way to sort these mp3 files by any ways:
- by name alphabetically (default)
- by date
we should be able to also create playlists of any mp3 files we select

So we should have also ways to select files in directory and some ui to allow us to either create new playlist or add selected to existing playlist.

The same in the playlist we should be able to change order of mp3 files to decide in what order to play them.

When we play songs we should have special view where we can see current playing mp3 file information (title, artist), and we should have controls to play, pause, stop, next, previous songs.

But very important: on top of the cover for mp3 file (extracted from mp3 file itself or just default thumbnail if doesn't exist). So on top of thumbnail we should have 4 buttons covering entire surface of cover (make these pressable/clickable areas big, to easly press them in the car).

So top two buttons (biggest) should move 3 sec back or forward.
Bottom two big buttons should move to the previous song or next song.

Where pressing "previous song" button when song playing is more then 5 first seconds should just restart song. Otherwise it should move to previous song.

Also I need god integration with iphone media control.

I have device in the car which have physical buttons :
- play/pause
- next song
- previous song

I would like to use quick press of 'next song' to forward 3 sec, and pressing 'previous song' fast to move 3 sec back.
The same when pressed long it should move to next/previous song.

Songs should be playable when i lock the screen. so I guess it should integrate properly with iphone media playing system.

So again: two main sections:
- directory/play
- playlists
in both control over ordering songs (defaul by name alphabetical).
From playlist we can remove song. (it will not remove file physically, in fact we can't remove them physicall from our app). just remove from playlist.

# Problems before

I've already tried in the past to create such app with AI. And I ran into issues:
- when user select subset of songs there was not clear button to 'add to the playlist' selected songs (and create new playlist along the way or point to existing ones)
- when manually rewinding with scrollbar (progress bar) to different place in the mp4 app no longer updated the scrollbar (progress bar) to reflect current timestamp mp3 is playing.

Try to avoid these issues.

# Parts to figure out
I'm not sure what is most standard way to store data like what directory was imported (importing ideally without making copy of files from 'files' app in our app. just tap in to the existing folder).
And where to store playlists and ordering for directories and playlist. 
Use most standard way to store this data. if you can explain what are options why you choose specific one.

# icon
Generate some reasonable icon for the app. CAn be vector graphis, whatever will be suitable. Ideally maybe some music note motive.

# when app is running
prevent locking screen
remember where I've finished

# selection
- Select by regex: allow providing a regex pattern in a popup/dialog to match and select files by name, provide regex examples in the UI, and remember the last used regex value between usages.

# theme
- Use warm brown and vibrant orange as the primary accent colors and gradients throughout the app.
