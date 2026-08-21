//go:build loadtest

// Comptabilité CPU du harnais de charge (STR-243).
//
// L'ADR 016 mesurait la latence, la mémoire et les goroutines, mais jamais le
// processeur — alors que le sujet pose la question en euros : « combien nous
// coûte en CPU le streaming de 100 flux simultanés ? ». Ce fichier fournit
// l'instrument ; streams_test.go s'en sert pour le modèle de coût.
package loadtest

import (
	"fmt"
	"os/exec"
	"runtime/debug"
	"syscall"
	"time"
)

// cpuUsage : temps CPU cumulé depuis le démarrage du process de test, séparé
// entre le process lui-même et ses fils.
//
// La séparation n'est pas cosmétique. Dans ce harnais in-process, le process Go
// EST le serveur, tandis que la segmentation HLS vit dans des process ffmpeg
// fils (ADR 015). Un `Getrusage(RUSAGE_SELF)` seul aurait donc raté l'essentiel
// du coût d'un flux et produit exactement le « CPU ~0 » qualitatif que ce
// ticket reproche à l'ADR 015.
type cpuUsage struct {
	self     time.Duration // le serveur Go : parsing HTTP, JWT, service de fichiers
	children time.Duration // les ffmpeg : segmentation, et transcodage si non-AAC
}

func (c cpuUsage) total() time.Duration { return c.self + c.children }

func (c cpuUsage) sub(o cpuUsage) cpuUsage {
	return cpuUsage{self: c.self - o.self, children: c.children - o.children}
}

// readCPU lit les compteurs rusage du noyau.
//
// ⚠️ RUSAGE_CHILDREN ne comptabilise que les fils **terminés et récoltés**
// (wait(2)) : un ffmpeg encore vivant n'y figure pas, et un ffmpeg jamais
// attendu n'y figurerait jamais. Deux conséquences, toutes deux structurantes
// pour la façon dont ce harnais mesure :
//
//  1. Impossible d'échantillonner « le CPU pendant la fenêtre de charge » comme
//     on échantillonne le tas. La mesure ne peut être que globale, prise APRÈS
//     l'arrêt des sessions. D'où le protocole de streams_test.go : durée de
//     diffusion identique pour tous les N, et lecture du coût marginal dans la
//     PENTE plutôt que dans une valeur absolue.
//  2. Le résultat dépend du fait que le serveur récolte ses process. C'est le
//     cas : hls.go lance un `cmd.Wait()` dédié à la création du segmenteur, et
//     transcode.go fait de même. Un ffmpeg zombie serait invisible ici — ce
//     serait aussi une fuite de process, que le test de fuite couvre par
//     ailleurs.
func readCPU() (cpuUsage, error) {
	var self, children syscall.Rusage
	if err := syscall.Getrusage(syscall.RUSAGE_SELF, &self); err != nil {
		return cpuUsage{}, fmt.Errorf("getrusage(SELF): %w", err)
	}
	if err := syscall.Getrusage(syscall.RUSAGE_CHILDREN, &children); err != nil {
		return cpuUsage{}, fmt.Errorf("getrusage(CHILDREN): %w", err)
	}
	return cpuUsage{self: rusageCPU(&self), children: rusageCPU(&children)}, nil
}

// rusageCPU somme temps utilisateur et temps système : les deux sont facturés
// par l'hébergeur, et la segmentation HLS écrit beaucoup (donc du `sys`).
func rusageCPU(ru *syscall.Rusage) time.Duration {
	return timevalDuration(ru.Utime) + timevalDuration(ru.Stime)
}

// timevalDuration convertit un timeval sans supposer la largeur de ses champs :
// Usec est un int32 sur darwin et un int64 sur linux.
func timevalDuration(tv syscall.Timeval) time.Duration {
	return time.Duration(tv.Sec)*time.Second + time.Duration(tv.Usec)*time.Microsecond
}

// processCPU rend le temps CPU d'un process terminé et récolté. Sert à
// DÉFALQUER le générateur de charge : les ffmpeg qui fabriquent l'audio de test
// sont des fils du harnais au même titre que ceux du serveur, et RUSAGE_CHILDREN
// les additionne sans distinction. Sans cette soustraction, le coût mesuré
// « par flux » embarquerait un encodeur qui n'existe pas en production — le
// diffuseur, lui, encode sur SA machine.
func processCPU(cmd *exec.Cmd) time.Duration {
	if cmd == nil || cmd.ProcessState == nil {
		return 0
	}
	return cmd.ProcessState.UserTime() + cmd.ProcessState.SystemTime()
}

// cores exprime un temps CPU en cœurs moyens occupés sur une fenêtre : c'est
// l'unité qui se convertit directement en vCPU facturés.
func cores(cpu, wall time.Duration) float64 {
	if wall <= 0 {
		return 0
	}
	return float64(cpu) / float64(wall)
}

// raceEnabled indique si le binaire de test a été compilé avec le détecteur de
// données. Il multiplie le temps CPU du code Go par un ordre de grandeur sans
// toucher à celui des process ffmpeg : la mesure ne serait pas décalée d'un
// facteur d'échelle rattrapable, mais DÉFORMÉE entre ses deux termes.
//
// Lu dans les réglages de build, et non via une paire de fichiers sous
// `//go:build race` / `//go:build !race`. Trois raisons, dans cet ordre :
//
//  1. `race` n'est pas un tag qu'on passe à `-tags` — c'est le toolchain qui le
//     pose sous `-race`. La garde DECLARED_TAGS de la CI exige que tout tag
//     présent dans l'arbre y soit déclaré ; l'y ajouter aurait fait tourner
//     `go vet -tags …,race` sans détecteur actif, c'est-à-dire mentir au
//     système de build pour faire taire un garde-fou.
//  2. La CI ne compile qu'une variante par tag. Le fichier `//go:build race`
//     n'aurait donc jamais été vérifié — très exactement la pourriture
//     silencieuse que la garde existe pour attraper (cf. ADR 016).
//  3. Une fonction se teste dans les deux sens ; une constante sous build tag,
//     non.
func raceEnabled() bool {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return false
	}
	for _, s := range info.Settings {
		if s.Key == "-race" {
			return s.Value == "true"
		}
	}
	return false
}
