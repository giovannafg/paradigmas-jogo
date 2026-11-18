// Ponto de entrada JavaScript. O Vite começa por aqui (veja index.html).
// Todo o visual do jogo está em um arquivo só.
import "./style.css";

// O vite-plugin-elm permite importar um módulo Elm como se fosse JS: ele
// compila src/Main.elm e recompila a cada alteração (hot reload).
import { Elm } from "./Main.elm";

// Tema inicial: a última escolha do jogador (guardada no localStorage do
// navegador) ou, na primeira visita, a preferência do sistema operacional.
const THEME_KEY = "bce-theme";
const savedTheme = localStorage.getItem(THEME_KEY);
const systemIsDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
const darkTheme = savedTheme ? savedTheme === "dark" : systemIsDark;

// `flags` é entregue à função `init` do Elm (veja o tipo Flags em Main.elm).
Elm.Main.init({
  node: document.getElementById("app"),
  flags: { darkTheme },
});

// Guarda a escolha quando o botão de tema muda. Ouvimos o evento no
// `document` inteiro ("delegação de eventos") porque o checkbox é criado pelo
// Elm e pode ser recriado a qualquer momento.
//
// Isto poderia ser feito com uma PORT do Elm (um canal de mensagens entre Elm
// e JavaScript), mas para algo tão simples o JavaScript sozinho basta.
document.addEventListener("change", (event) => {
  if (event.target.matches(".theme-controller")) {
    localStorage.setItem(THEME_KEY, event.target.checked ? "dark" : "light");
  }
});
