// ==UserScript==
// @name         Estratégia Concursos - Full HD & Auto Próximo
// @namespace    http://tampermonkey.net/
// @version      12.2
// @description  Força melhor qualidade disponível e avança para o próximo vídeo/aula automaticamente ao finalizar
// @author       Você
// @match        https://*.estrategiaconcursos.com.br/*
// @match        https://www.estrategiaconcursos.com.br/*
// @grant        none
// @run-at       document-idle
// ==/UserScript==

(function() {
    'use strict';

    // ========== CONFIGURAÇÕES ==========
    const CONFIG = {
        CHECK_INTERVAL: 2000,
        VIDEO_END_TOLERANCE: 2,        // Aumentado para 2s (melhor compatibilidade com 3x)
        TRANSITION_LOCK_TIME: 8000,
        PREFERRED_QUALITIES: ['1080', '720', '480'],  // 1080 tentado primeiro, fallback automático
        AUTO_HD: true,
        FORCE_RESTART_ON_NEW_VIDEO: true,
        FULLSCREEN_SHORTCUT: 'f'         // Tecla para alternar fullscreen (pressione F)
    };

    // ========== ESTADO ==========
    let state = {
        isTransitioning: false,
        currentVideoUrl: null,
        qualityApplied: false,
        userPaused: false,
        lastVideoCheck: 0,
        qualityBeingChanged: false,
        videoListenerAttached: false,    // Rastreia se o listener já está no <video> atual
        needsAutoPlay: false             // Sinaliza que o próximo vídeo deve dar play automático
    };

    // ========== FUNÇÃO 1: FORÇAR QUALIDADE ==========
    function setVideoQuality() {
        if (!CONFIG.AUTO_HD || state.qualityApplied || state.qualityBeingChanged) return;

        const settingsButton = document.querySelector('.PlayerControl-button[aria-label="Alterar qualidade"]');
        if (!settingsButton) return;

        state.qualityBeingChanged = true;
        console.log('[AutoScript] 🔧 Iniciando ajuste de qualidade...');

        settingsButton.click();

        setTimeout(() => {
            const qualityButtons = Array.from(document.querySelectorAll('.PlayerControlOptions-button'));

            if (qualityButtons.length === 0) {
                console.log('[AutoScript] ⚠️ Menu de qualidade vazio, fechando...');
                settingsButton.click();
                state.qualityBeingChanged = false;
                return;
            }

            // Log das qualidades disponíveis
            const available = qualityButtons.map(b => b.textContent.trim()).join(', ');
            console.log(`[AutoScript] 📋 Qualidades disponíveis: ${available}`);

            let targetButton = null;
            let selectedQuality = null;
            for (const quality of CONFIG.PREFERRED_QUALITIES) {
                targetButton = qualityButtons.find(btn =>
                    btn.textContent.includes(quality) && !btn.classList.contains('isActive')
                );
                if (targetButton) {
                    selectedQuality = quality;
                    break;
                }
                // Se a qualidade preferida já está ativa, considerar como aplicada
                const activeBtn = qualityButtons.find(btn =>
                    btn.textContent.includes(quality) && btn.classList.contains('isActive')
                );
                if (activeBtn) {
                    console.log(`[AutoScript] ✅ Qualidade ${quality}p já está ativa`);
                    settingsButton.click();
                    state.qualityApplied = true;
                    state.qualityBeingChanged = false;
                    return;
                }
            }

            if (targetButton) {
                console.log(`[AutoScript] 🎥 Aplicando qualidade: ${selectedQuality}p`);
                targetButton.click();
                state.qualityApplied = true;

                setTimeout(() => {
                    // Fecha o menu se ainda estiver aberto
                    const menuStillOpen = document.querySelector('.PlayerControlOptions');
                    if (menuStillOpen && menuStillOpen.offsetParent !== null) {
                        settingsButton.click();
                    }
                    console.log('[AutoScript] ✅ Qualidade aplicada com sucesso');

                    setTimeout(() => {
                        state.qualityBeingChanged = false;
                    }, 1000);
                }, 300);
            } else {
                settingsButton.click();
                state.qualityApplied = true;
                state.qualityBeingChanged = false;
                console.log('[AutoScript] ℹ️ Nenhuma qualidade melhor disponível');
            }
        }, 300);
    }

    // ========== FUNÇÃO 2: OBTER IDENTIFICADOR DO VÍDEO ==========
    function getVideoIdentifier() {
        // Usa a URL da página: /cursos/358522/aulas/3565337/videos/259488
        const match = window.location.pathname.match(/\/videos\/(\d+)/);
        return match ? match[1] : null;
    }

    // ========== FUNÇÃO 3: DETECTAR NOVO VÍDEO ==========
    function checkForNewVideo() {
        const video = document.querySelector('video');
        if (!video || !video.duration) return;

        const currentVideoId = getVideoIdentifier();
        if (!currentVideoId) return;

        const isNewVideo = state.currentVideoUrl !== currentVideoId;

        // Evita múltiplas detecções no mesmo segundo
        const now = Date.now();
        const timeSinceLastCheck = now - state.lastVideoCheck;

        if (isNewVideo && timeSinceLastCheck > 3000) {
            state.currentVideoUrl = currentVideoId;
            state.qualityApplied = false;
            state.userPaused = false;
            state.lastVideoCheck = now;

            console.log(`[AutoScript] 🔄 Novo vídeo detectado (ID: ${currentVideoId})`);

            // Re-anexa listeners caso o React tenha recriado o <video>
            attachVideoListeners(video);

            // Força reinício
            if (CONFIG.FORCE_RESTART_ON_NEW_VIDEO && video.currentTime > 2) {
                console.log('[AutoScript] ⏮️ Reiniciando vídeo do começo...');
                video.currentTime = 0;
            }

            // Aguarda o vídeo estar pronto antes de ajustar qualidade e dar play
            const waitForVideoReady = setInterval(() => {
                const freshVideo = document.querySelector('video');
                if (freshVideo && freshVideo.readyState >= 2 && !state.qualityBeingChanged) {
                    clearInterval(waitForVideoReady);
                    console.log('[AutoScript] ⏳ Vídeo pronto, aplicando configurações...');

                    // Auto-play se veio de uma transição automática
                    if (state.needsAutoPlay) {
                        state.needsAutoPlay = false;
                        autoPlayVideo(freshVideo);
                    }

                    setTimeout(() => {
                        if (CONFIG.AUTO_HD) {
                            setVideoQuality();
                        }
                    }, 500);
                }
            }, 100);

            // Timeout de segurança
            setTimeout(() => clearInterval(waitForVideoReady), 10000);
        }
    }

    // ========== FUNÇÃO 4: AVANÇAR PARA PRÓXIMO VÍDEO OU AULA ==========
    function goToNextVideo() {
        if (state.isTransitioning || state.qualityBeingChanged) return;

        const video = document.querySelector('video');
        if (!video || !video.duration) return;

        const timeRemaining = video.duration - video.currentTime;
        const isEnded = video.ended || timeRemaining <= CONFIG.VIDEO_END_TOLERANCE;

        if (!isEnded) return;

        console.log('[AutoScript] ✅ Vídeo finalizado. Buscando próximo...');

        // TENTATIVA 1: Próximo vídeo na mesma aula
        const currentSelected = document.querySelector('.VideoItem.isSelected');
        if (currentSelected) {
            const currentWrapper = currentSelected.closest('.ListVideos-items-video');
            if (currentWrapper) {
                const nextWrapper = currentWrapper.nextElementSibling;
                if (nextWrapper) {
                    const nextLink = nextWrapper.querySelector('.VideoItem');
                    if (nextLink) {
                        advanceTo(nextLink, 'próximo vídeo');
                        return;
                    }
                }
            }
        }

        // TENTATIVA 2: Próxima aula
        console.log('[AutoScript] 📚 Fim dos vídeos desta aula. Buscando próxima aula...');

        const openedCollapse = document.querySelector('.Collapse.isOpened');
        if (!openedCollapse) {
            console.log('[AutoScript] ⚠️ Aula atual não identificada');
            return;
        }

        const currentLesson = openedCollapse.closest('.LessonList-item');
        if (!currentLesson) {
            console.log('[AutoScript] ⚠️ Container da aula não encontrado');
            return;
        }

        const nextLesson = currentLesson.nextElementSibling;
        if (!nextLesson) {
            console.log('[AutoScript] 🏁 Fim de todas as aulas do curso!');
            return;
        }

        // Clica no link da próxima aula (navega para a página da aula)
        const nextLessonLink = nextLesson.querySelector('.Collapse-header');
        if (nextLessonLink) {
            advanceTo(nextLessonLink, 'próxima aula');
        } else {
            console.log('[AutoScript] ⚠️ Link da próxima aula não encontrado');
        }
    }

    // ========== FUNÇÃO AUXILIAR: EXECUTAR AVANÇO ==========
    function advanceTo(element, description) {
        state.isTransitioning = true;
        state.userPaused = false;
        state.qualityApplied = false;
        state.currentVideoUrl = null;
        state.lastVideoCheck = 0;
        state.videoListenerAttached = false;
        state.needsAutoPlay = true;      // Sinaliza auto-play para o próximo vídeo

        console.log(`[AutoScript] ▶️ Avançando para ${description}...`);

        element.click();

        // Fallback: tenta dar play diretamente após a navegação carregar
        setTimeout(() => {
            const video = document.querySelector('video');
            if (video && video.paused && !state.userPaused) {
                autoPlayVideo(video);
            }
        }, 3000);

        setTimeout(() => {
            state.isTransitioning = false;
            console.log('[AutoScript] 🔓 Pronto para próximo avanço');
        }, CONFIG.TRANSITION_LOCK_TIME);
    }

    // ========== FUNÇÃO AUXILIAR: AUTO-PLAY ==========
    function autoPlayVideo(video) {
        if (!video || !video.paused) return;

        console.log('[AutoScript] ▶️ Iniciando reprodução automática...');

        const playPromise = video.play();
        if (playPromise !== undefined) {
            playPromise.then(() => {
                console.log('[AutoScript] ✅ Reprodução automática iniciada');
            }).catch(err => {
                console.log('[AutoScript] ⚠️ Auto-play bloqueado pelo navegador:', err.message);
                console.log('[AutoScript] 💡 Tentando via botão de play do player...');

                // Fallback: clica no botão de play do video-react
                const playButton = document.querySelector('.video-react-play-control.video-react-paused');
                if (playButton) {
                    playButton.click();
                    console.log('[AutoScript] ✅ Play via botão do player');
                }
            });
        }
    }

    // ========== FULLSCREEN VIA CSS (PERSISTENTE) ==========
    let isCustomFullscreen = false;
    const FULLSCREEN_STYLE_ID = 'autoscript-fullscreen-style';

    function injectFullscreenCSS() {
        if (document.getElementById(FULLSCREEN_STYLE_ID)) return;

        const style = document.createElement('style');
        style.id = FULLSCREEN_STYLE_ID;
        style.textContent = `
            .autoscript-fullscreen .LessonVideos-player {
                position: fixed !important;
                top: 0 !important;
                left: 0 !important;
                width: 100vw !important;
                height: 100vh !important;
                z-index: 999999 !important;
                background: #000 !important;
            }
            .autoscript-fullscreen .LessonVideos-player .Player,
            .autoscript-fullscreen .LessonVideos-player .video-react {
                width: 100% !important;
                height: 100% !important;
                padding-top: 0 !important;
            }
            .autoscript-fullscreen .LessonVideos-player video {
                width: 100% !important;
                height: 100% !important;
                object-fit: contain !important;
            }
            .autoscript-fullscreen .LessonVideos-player .video-react-control-bar {
                position: absolute !important;
                bottom: 0 !important;
                width: 100% !important;
                z-index: 1000000 !important;
            }
            body.autoscript-fullscreen {
                overflow: hidden !important;
            }
        `;
        document.head.appendChild(style);
    }

    function toggleCustomFullscreen() {
        isCustomFullscreen = !isCustomFullscreen;
        document.body.classList.toggle('autoscript-fullscreen', isCustomFullscreen);
        console.log(`[AutoScript] 🖥️ Fullscreen ${isCustomFullscreen ? 'ATIVADO' : 'DESATIVADO'} (tecla F)`);
    }

    function setupKeyboardShortcuts() {
        injectFullscreenCSS();

        document.addEventListener('keydown', (e) => {
            // Ignora se estiver digitando em input/textarea
            const tag = e.target.tagName.toLowerCase();
            if (tag === 'input' || tag === 'textarea' || e.target.isContentEditable) return;

            if (e.key.toLowerCase() === CONFIG.FULLSCREEN_SHORTCUT) {
                e.preventDefault();
                toggleCustomFullscreen();
            }

            // ESC para sair do fullscreen customizado
            if (e.key === 'Escape' && isCustomFullscreen) {
                e.preventDefault();
                toggleCustomFullscreen();
            }
        });
        console.log(`[AutoScript] ⌨️ Atalho: "${CONFIG.FULLSCREEN_SHORTCUT.toUpperCase()}" para fullscreen | ESC para sair`);
    }

    // ========== FUNÇÃO 5: ANEXAR LISTENERS AO VÍDEO ==========
    function attachVideoListeners(video) {
        if (!video) return;

        // Evita duplicação de listeners usando data attribute
        if (video.dataset.autoScriptAttached === 'true') return;
        video.dataset.autoScriptAttached = 'true';

        video.addEventListener('pause', () => {
            if (!state.isTransitioning && !state.qualityBeingChanged && !video.ended) {
                state.userPaused = true;
                console.log('[AutoScript] ⏸️ Usuário pausou o vídeo');
            }
        });

        video.addEventListener('play', () => {
            if (state.userPaused) {
                state.userPaused = false;
                console.log('[AutoScript] ▶️ Usuário retomou o vídeo');
            }
        });

        console.log('[AutoScript] 🎧 Listeners de vídeo configurados');
    }

    // ========== FUNÇÃO 6: MUTATION OBSERVER (SPA) ==========
    function setupMutationObserver() {
        const observer = new MutationObserver(() => {
            const video = document.querySelector('video');
            if (video && video.dataset.autoScriptAttached !== 'true') {
                console.log('[AutoScript] 🔍 Novo elemento <video> detectado no DOM');
                attachVideoListeners(video);
            }
        });

        observer.observe(document.body, { childList: true, subtree: true });
        console.log('[AutoScript] 👁️ MutationObserver ativo (monitorando SPA)');
    }

    // ========== FUNÇÃO 7: INICIALIZAÇÃO ==========
    function waitForVideo() {
        const video = document.querySelector('video');
        if (video) {
            console.log('[AutoScript] 🎬 Player de vídeo detectado!');
            state.currentVideoUrl = getVideoIdentifier();
            attachVideoListeners(video);
            startMonitoring();
        } else {
            setTimeout(waitForVideo, 1000);
        }
    }

    // ========== LOOP PRINCIPAL ==========
    function startMonitoring() {
        setInterval(() => {
            if (state.userPaused || state.qualityBeingChanged) {
                return;
            }

            checkForNewVideo();
            goToNextVideo();
        }, CONFIG.CHECK_INTERVAL);

        console.log('[AutoScript] 🚀 Monitoramento iniciado!');
        console.log(`[AutoScript] ⚙️ HD Automático: ${CONFIG.AUTO_HD ? 'ATIVADO' : 'DESATIVADO'}`);
        console.log(`[AutoScript] ⚙️ Reinício Automático: ${CONFIG.FORCE_RESTART_ON_NEW_VIDEO ? 'ATIVADO' : 'DESATIVADO'}`);
    }

    // ========== INICIALIZAÇÃO ==========
    console.log('[AutoScript] 📺 Script v12.3 carregado - Aguardando player...');
    setupMutationObserver();
    setupKeyboardShortcuts();
    waitForVideo();

})();
