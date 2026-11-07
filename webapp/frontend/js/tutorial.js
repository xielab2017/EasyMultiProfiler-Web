const video = document.getElementById('tutorial');
const failure = document.getElementById('failure');
const fail = () => { failure.hidden = false; };
video.addEventListener('error', fail);
video.querySelector('source').addEventListener('error', fail);
video.addEventListener('loadedmetadata', () => { failure.hidden = true; });
for (const language of ['en', 'zh', 'off']) {
  document.getElementById(`captions-${language}`).addEventListener('click', () => {
    for (const track of video.textTracks) track.mode = track.language === language ? 'showing' : 'disabled';
  });
}
