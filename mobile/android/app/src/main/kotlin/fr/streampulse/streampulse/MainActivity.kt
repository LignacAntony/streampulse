package fr.streampulse.streampulse

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service exige que l'Activity hôte étende AudioServiceActivity pour que
// le service de premier plan de lecture (STR-109) se rattache correctement.
class MainActivity : AudioServiceActivity()
