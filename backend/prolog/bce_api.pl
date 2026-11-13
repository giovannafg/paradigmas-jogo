/*  bce_api.pl: Tradução entre o JSON da API e o modelo de bce.pl.

    O janus (ver backend/app/prolog.py) só troca inteiros, strings e listas
    com o Python. O bce.pl, por outro lado, trabalha com ÁTOMOS (arthur,
    porta) e com o termo composto mesa/3. Este módulo faz a ponte nos dois
    sentidos, para que nem o Python precise conhecer termos do Prolog nem o
    bce.pl precise saber que existe uma API.

    Nenhuma regra do jogo mora aqui, com uma exceção pequena: quem já começa
    sentado (os "fixos") não pode sair do lugar. O bce.pl não distingue
    fixos de sentados, então é aqui que conferimos.

    O formato completo do JSON está em docs/API.md.

    COMO TESTAR NO TERMINAL
    -----------------------
        $ swipl backend/prolog/bce_api.pl
        ?- nova_fase("facil", L, C, Objs, Amigos, Fixos, Manias).
        ?- estado(2, 3, [["porta",0,0],["tomada",0,2]],
                  ["arthur","joao","mayara","bevi"], [["bevi",1,1]],
                  [["bevi",1,1],["joao",0,2]], R).
*/

:- module(bce_api,
          [ nova_fase/7,         % +Dificuldade, -L, -C, -Objetos, -Amigos, -Fixos, -Manias
            estado/7,            % +L, +C, +Objetos, +Amigos, +Fixos, +Sentados, -Resultado
            jogada/10,           % +L, +C, +Objetos, +Amigos, +Fixos, +Sentados,
                                 % +Amigo, +Linha, +Coluna, -Resultado
            dica/7,              % +L, +C, +Objetos, +Amigos, +Fixos, +Sentados, -Resultado
            resolver/7           % +L, +C, +Objetos, +Amigos, +Fixos, +Sentados, -Resultado
          ]).

:- use_module(bce).
:- use_module(library(apply)).
:- use_module(library(lists)).


/* =========================================================================
   NOVA FASE
   ========================================================================= */

%!  nova_fase(+Dificuldade, -L, -C, -Objetos, -Amigos, -Fixos, -Manias) is det.
%
%   Enquanto o gerador (#6) não fica pronto, toda dificuldade devolve a fase
%   de exemplo do bce.pl. Assim o Elm já consegue jogar de ponta a ponta.
%   Quando o #6 entrar, só esta cláusula muda; o JSON continua igual.
%
%   Manias = [[Amigo, Tipo, Args], ...], em que Args é a lista de
%   argumentos do termo da mania: perto_de_objeto(porta) vira
%   [arthur, perto_de_objeto, [porta]] e sem_vizinhos vira
%   [bevi, sem_vizinhos, []].
nova_fase(_Dificuldade, L, C, Objetos, Amigos, Fixos, Manias) :-
    fase_exemplo(mesa(L, C, Objetos), Amigos, Fixos),
    manias_da_fase(Amigos, Manias).

manias_da_fase(Amigos, Manias) :-
    findall([Amigo, Tipo, Args],
            ( member(Amigo, Amigos),
              mania(Amigo, Mania),
              Mania =.. [Tipo | Args]
            ),
            Manias).


/* =========================================================================
   ESTADO E JOGADA
   ========================================================================= */

%!  estado(+L, +C, +Objetos, +Amigos, +Fixos, +Sentados, -Resultado) is det.
%
%   Resultado é o átomo `invalido` ou a lista [Sentados, Status, Venceu],
%   com Venceu = true/false. Sentados inclui os fixos.
estado(L, C, Objetos0, Amigos0, Fixos0, Sentados0, Resultado) :-
    (   valida(L, C, Objetos0, Amigos0, Fixos0, Sentados0,
               Mesa, Amigos, Sentados)
    ->  resultado(Mesa, Amigos, Sentados, Resultado)
    ;   Resultado = invalido
    ).

%!  jogada(+L, +C, +Objetos, +Amigos, +Fixos, +Sentados,
%!         +Amigo, +Linha, +Coluna, -Resultado) is det.
%
%   Senta Amigo em (Linha, Coluna). Resultado é `invalido` quando o estado
%   recebido já é inválido, `jogada_invalida` quando a jogada não é
%   permitida (cadeira ocupada, fora da mesa, amigo fora da fase ou já
%   sentado) e, se der certo, [NovosSentados, Status, Venceu].
jogada(L, C, Objetos0, Amigos0, Fixos0, Sentados0, Amigo0, Linha, Coluna,
       Resultado) :-
    estado(L, C, Objetos0, Amigos0, Fixos0, Sentados0, Atual),
    (   Atual == invalido
    ->  Resultado = invalido
    ;   traduz(L, C, Objetos0, Amigos0, Fixos0, Sentados0,
               Mesa, Amigos, _, Sentados),
        atom_string(Amigo, Amigo0),
        jogada_valida(Mesa, Amigos, Sentados, Amigo, [Linha, Coluna])
    ->  resultado(Mesa, Amigos, [[Amigo, Linha, Coluna] | Sentados], Resultado)
    ;   Resultado = jogada_invalida
    ).

resultado(Mesa, Amigos, Sentados, [Sentados, Status, Venceu]) :-
    status_manias(Mesa, Amigos, Sentados, Status),
    (   venceu(Mesa, Amigos, Sentados)
    ->  Venceu = true
    ;   Venceu = false
    ).

%   Traduz o JSON e confere se o estado pode existir. Usado por todas as
%   rotas que recebem um estado, para elas recusarem os mesmos casos.
valida(L, C, Objetos0, Amigos0, Fixos0, Sentados0, Mesa, Amigos, Sentados) :-
    traduz(L, C, Objetos0, Amigos0, Fixos0, Sentados0,
           Mesa, Amigos, Fixos, Sentados),
    estado_valido(Mesa, Amigos, Sentados),
    fixos_no_lugar(Fixos, Sentados).

%   Cada fixo tem que estar em Sentados, na mesma cadeira.
fixos_no_lugar(Fixos, Sentados) :-
    forall(member(Fixo, Fixos), memberchk(Fixo, Sentados)).


/* =========================================================================
   DICA
   ========================================================================= */

%!  dica(+L, +C, +Objetos, +Amigos, +Fixos, +Sentados, -Resultado) is det.
%
%   Resultado é um dos átomos `invalido`, `completo`, `sem_solucao` e
%   `sem_jogada` (hint/4 falhou: nenhuma jogada é obrigatória), ou a lista
%   [Amigo, Linha, Coluna, Motivo]. Motivo é a mania que força a jogada, no
%   formato [Amigo, Tipo, Args] de nova_fase/7, ou [] quando só a mesa a
%   força.
dica(L, C, Objetos0, Amigos0, Fixos0, Sentados0, Resultado) :-
    (   valida(L, C, Objetos0, Amigos0, Fixos0, Sentados0,
               Mesa, Amigos, Sentados)
    ->  (   hint(Mesa, Amigos, Sentados, Dica)
        ->  dica_resultado(Dica, Resultado)
        ;   Resultado = sem_jogada
        )
    ;   Resultado = invalido
    ).

dica_resultado([completo], completo).
dica_resultado([sem_solucao], sem_solucao).
dica_resultado([sentar, Amigo, L, C, Dono], [Amigo, L, C, Motivo]) :-
    motivo(Dono, Motivo).

motivo(nenhuma, []) :-
    !.
motivo(Dono, [Dono, Tipo, Args]) :-
    mania(Dono, Mania),
    Mania =.. [Tipo | Args].


/* =========================================================================
   RESOLVER
   ========================================================================= */

%!  resolver(+L, +C, +Objetos, +Amigos, +Fixos, +Sentados, -Resultado) is det.
%
%   Resultado é `invalido`, `sem_solucao` ou [Solucao, Status, Venceu], no
%   mesmo formato de estado/7, com todos os amigos sentados.
resolver(L, C, Objetos0, Amigos0, Fixos0, Sentados0, Resultado) :-
    (   valida(L, C, Objetos0, Amigos0, Fixos0, Sentados0,
               Mesa, Amigos, Sentados)
    ->  (   once(solve(Mesa, Amigos, Sentados, Solucao))
        ->  resultado(Mesa, Amigos, Solucao, Resultado)
        ;   Resultado = sem_solucao
        )
    ;   Resultado = invalido
    ).


/* =========================================================================
   TRADUÇÃO DE STRINGS PARA ÁTOMOS
   =========================================================================

   atom_string/2 aceita tanto string quanto átomo no segundo argumento, então
   os mesmos predicados servem para testar no terminal com átomos.
*/

traduz(L, C, Objetos0, Amigos0, Fixos0, Sentados0,
       mesa(L, C, Objetos), Amigos, Fixos, Sentados) :-
    integer(L), integer(C),
    maplist(lugar_atomo, Objetos0, Objetos),
    maplist(nome_atomo, Amigos0, Amigos),
    maplist(lugar_atomo, Fixos0, Fixos),
    maplist(lugar_atomo, Sentados0, Sentados).

nome_atomo(Nome, Atomo) :-
    atom_string(Atomo, Nome).

lugar_atomo([Nome, L, C], [Atomo, L, C]) :-
    nome_atomo(Nome, Atomo).
