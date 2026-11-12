/*  bce.pl: Estado e regras do "Grupo de Estudo na BCE".

    O jogo está descrito em docs/REGRAS.md. Este arquivo modela a mesa, os
    amigos e as manias, e transforma as manias em restrições CLP(FD). O
    resolvedor (#5), o gerador (#6) e a dica (#7) usam o mesmo modelo, então
    uma regra é escrita uma vez só.

    REPRESENTAÇÃO
    -------------
    Os argumentos usam só inteiros, átomos e listas, porque são esses os
    tipos que o janus troca com o Python (ver backend/app/prolog.py).

        Mesa      mesa(Linhas, Colunas, Objetos)
                  Objetos = [[porta, 0, 0], [tomada, 0, 2]]
        Amigos    [arthur, joao, mayara, bevi]       quem está na fase
        Sentados  [[bevi, 1, 1]]                     [Amigo, Linha, Coluna]
        Status    [[arthur, ok], [mayara, pendente], [bevi, violada]]

    Linhas e colunas começam em 0, com (0,0) no canto de cima à esquerda.
    A cadeira do objeto é a cadeira onde ele está: um amigo pode sentar nela.

    A IDEIA CENTRAL: MANIAS SÃO DADOS
    ---------------------------------
    No Sudoku há uma regra só e ela fica no código. Aqui cada amigo tem uma
    regra diferente, então as manias são FATOS (mania/2), e um único
    interpretador, mania_vale/4, traduz cada tipo de mania numa restrição.
    Uma mania nova de um tipo que já existe é só mais um fato.

    O interpretador não diz "a mania vale" ou "não vale": ele liga a mania a
    uma variável booleana B (0 ou 1) por REIFICAÇÃO (#<==>). Com isso o mesmo
    código serve a dois usos:

        * resolver/gerar: exigimos B = 1 e o CLP(FD) procura as posições;
        * conferir uma jogada: as posições já são números e o CLP(FD) só
          calcula B, que vira ✅ (1) ou ❌ (0).

    COMO TESTAR NO TERMINAL
    -----------------------
        $ swipl backend/prolog/bce.pl
        ?- use_module(library(clpfd)).     % para label/1 no terminal
        ?- fase_exemplo(M, A, S), restricoes(M, A, S, L), lugares_vars(L, V),
           label(V).
        ?- fase_exemplo(M, A, S),
           status_manias(M, A, [[mayara,0,0],[arthur,0,1],[joao,0,2]|S], St).
*/

:- module(bce,
          [ mania/2,             % ?Amigo, ?Mania
            restricoes/4,        % +Mesa, +Amigos, +Sentados, -Lugares
            lugares_vars/2,      % +Lugares, -Vars
            estado_valido/3,     % +Mesa, +Amigos, +Sentados
            jogada_valida/5,     % +Mesa, +Amigos, +Sentados, +Amigo, +Cadeira
            status_manias/4,     % +Mesa, +Amigos, +Sentados, -Status
            venceu/3,            % +Mesa, +Amigos, +Sentados
            solve/4,             % +Mesa, +Amigos, +Sentados, -Solucao
            count_solutions/5,   % +Mesa, +Amigos, +Sentados, +Limite, -N
            generate/4,          % +Nivel, -Mesa, -Amigos, -Sentados
            hint/4,              % +Mesa, +Amigos, +Sentados, -Dica
            fase_exemplo/3       % -Mesa, -Amigos, -Sentados
          ]).

:- use_module(library(clpfd)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(solution_sequences)).
:- use_module(library(aggregate)).
:- use_module(library(random)).


/* =========================================================================
   1. BASE DE CONHECIMENTO
   ========================================================================= */

%!  amigo(?Amigo) is nondet.
amigo(arthur).
amigo(bevi).
amigo(felipe).
amigo(gabriel).
amigo(giovanna).
amigo(joao).
amigo(mayara).

%!  objeto(?Objeto) is nondet.
objeto(janela).
objeto(tomada).
objeto(porta).
objeto(estante).

%!  mania(?Amigo, ?Mania) is nondet.
%
%   A mania que cada integrante escolheu na issue #1. A frase original está
%   em docs/REGRAS.md; aqui fica só a forma que o interpretador entende.
mania(arthur,   perto_de_objeto(porta)).
mania(bevi,     sem_vizinhos).
mania(felipe,   de_frente_para_algum([arthur, joao])).
mania(gabriel,  perto_de(arthur)).
mania(giovanna, lado_a_lado_com(mayara)).
mania(joao,     na_cadeira_de(tomada)).
mania(mayara,   longe_de(joao)).


/* =========================================================================
   2. RELAÇÕES ENTRE CADEIRAS (vocabulário de posição)
   =========================================================================

   Uma cadeira é cad(Linha, Coluna). Cada relação devolve um booleano B
   reificado em vez de simplesmente ter sucesso ou falhar. Assim as manias
   podem combinar relações com "ou" (algum/2), "nenhum" (nenhum/2) e "não"
   (#\), coisas que não dá para dizer com um objetivo que só falha.

   Linha e coluna ficam separadas, em vez de um índice único da cadeira,
   porque assim toda relação vira uma restrição LINEAR sobre a diferença
   entre as coordenadas (DL, DC), calculada FORA da reificação. Uma versão
   anterior usava max(abs(...)) dentro do #<==> e, com 3 amigos, a
   propagação do CLP(FD) não terminava. Com diferenças e `in`, sim.
*/

%   diferenca(+Cad1, +Cad2, -DL, -DC): quanto Cad1 está abaixo e à direita
%   de Cad2. Como as coordenadas têm domínio finito, DL e DC também têm.
diferenca(cad(L1, C1), cad(L2, C2), DL, DC) :-
    DL #= L1 - L2,
    DC #= C1 - C2.

%   Mesma linha, colunas vizinhas.
lado_a_lado(Cad1, Cad2, B) :-
    diferenca(Cad1, Cad2, DL, DC),
    B #<==> (DL #= 0 #/\ DC in {-1, 1}).

%   Mesma coluna, linhas vizinhas.
de_frente(Cad1, Cad2, B) :-
    diferenca(Cad1, Cad2, DL, DC),
    B #<==> (DC #= 0 #/\ DL in {-1, 1}).

%   Uma das até 8 cadeiras ao redor, sem contar a própria.
perto(Cad1, Cad2, B) :-
    diferenca(Cad1, Cad2, DL, DC),
    B #<==> (DL in -1..1 #/\ DC in -1..1 #/\ #\ (DL #= 0 #/\ DC #= 0)).

%   Perto de um OBJETO inclui sentar na própria cadeira dele (REGRAS.md).
perto_ou_na(Cad1, Cad2, B) :-
    diferenca(Cad1, Cad2, DL, DC),
    B #<==> (DL in -1..1 #/\ DC in -1..1).

na_mesma(Cad1, Cad2, B) :-
    diferenca(Cad1, Cad2, DL, DC),
    B #<==> (DL #= 0 #/\ DC #= 0).

%   algum(+Bs, -B): B é 1 se pelo menos um dos booleanos for 1.
%   Lista vazia dá 0, mas as manias tratam esse caso antes (ver seção 3).
algum(Bs, B) :-
    sum(Bs, #=, S),
    B #<==> (S #>= 1).

%   nenhum(+Bs, -B): B é 1 se todos os booleanos forem 0.
nenhum(Bs, B) :-
    sum(Bs, #=, S),
    B #<==> (S #= 0).


/* =========================================================================
   3. INTERPRETADOR DE MANIAS
   =========================================================================

   mania_vale(+Mania, +Amigo, +Ctx, -B) liga B à mania de Amigo.

   Ctx = ctx(Objetos, Lugares), em que Objetos são pares Objeto-cad(L, C) e
   Lugares são pares Amigo-cad(L, C) com os amigos considerados. As cadeiras
   em Lugares podem ser variáveis (resolver) ou números (conferir jogada).

   Regra geral (REGRAS.md): uma mania só restringe se o que ela cita está na
   fase. Amigo citado fora da fase, ou objeto que não existe na mesa, faz a
   mania valer automaticamente (B = 1). Por isso cada cláusula testa a lista
   vazia ANTES de chamar algum/2.
*/

mania_vale(perto_de_objeto(Objeto), Eu, Ctx, B) :-
    com_objeto(Objeto, perto_ou_na, Eu, Ctx, B).
mania_vale(na_cadeira_de(Objeto), Eu, Ctx, B) :-
    com_objeto(Objeto, na_mesma, Eu, Ctx, B).
mania_vale(sem_vizinhos, Eu, Ctx, B) :-
    %   Só olha quem está em Ctx: quem ainda não sentou não é vizinho de
    %   ninguém. Por isso esta mania não depende de outros amigos (seção 5).
    cadeira_de(Ctx, Eu, Minha),
    outros_lugares(Ctx, Eu, Outras),
    maplist(lado_a_lado(Minha), Outras, Bs),
    nenhum(Bs, B).
mania_vale(de_frente_para_algum(Amigos), Eu, Ctx, B) :-
    com_amigos(Amigos, de_frente, Eu, Ctx, B).
mania_vale(perto_de(Amigo), Eu, Ctx, B) :-
    com_amigos([Amigo], perto, Eu, Ctx, B).
mania_vale(lado_a_lado_com(Amigo), Eu, Ctx, B) :-
    com_amigos([Amigo], lado_a_lado, Eu, Ctx, B).
mania_vale(longe_de(Amigo), Eu, Ctx, B) :-
    %   "Longe" é a negação de "perto". Se o amigo não está na fase,
    %   com_amigos/5 dá Perto = 1 e a negação daria 0; por isso a ausência
    %   é tratada aqui, antes de negar.
    (   lugar_de(Ctx, Amigo, _)
    ->  com_amigos([Amigo], perto, Eu, Ctx, Perto),
        B #<==> #\ Perto
    ;   B = 1
    ).

%   com_objeto(+Objeto, +Relacao, +Eu, +Ctx, -B): Eu está na Relacao com
%   ALGUMA cadeira que tem Objeto (pode haver duas tomadas, por exemplo).
com_objeto(Objeto, Relacao, Eu, Ctx, B) :-
    Ctx = ctx(Objetos, _),
    cadeira_de(Ctx, Eu, Minha),
    %   Cadeiras de objetos são sempre números, então findall/3 é seguro.
    findall(Cad, member(Objeto-Cad, Objetos), Cads),
    (   Cads == []
    ->  B = 1
    ;   maplist(call(Relacao, Minha), Cads, Bs),
        algum(Bs, B)
    ).

%   com_amigos(+Amigos, +Relacao, +Eu, +Ctx, -B): Eu está na Relacao com
%   ALGUM dos Amigos citados que estão em Ctx.
%
%   Aqui NÃO dá para usar findall/3: ele devolve CÓPIAS dos termos, e a
%   cópia de uma cadeira cad(L, C) teria variáveis novas, sem as restrições
%   das originais. include/3 e exclude/3 devolvem os próprios elementos.
com_amigos(Amigos, Relacao, Eu, Ctx, B) :-
    Ctx = ctx(_, Lugares),
    cadeira_de(Ctx, Eu, Minha),
    include(lugar_de_algum(Amigos), Lugares, Citados),
    pairs_values(Citados, Cads),
    (   Cads == []
    ->  B = 1
    ;   maplist(call(Relacao, Minha), Cads, Bs),
        algum(Bs, B)
    ).

lugar_de(ctx(_, Lugares), Amigo, Cad) :-
    memberchk(Amigo-Cad, Lugares).

cadeira_de(Ctx, Amigo, Cad) :-
    lugar_de(Ctx, Amigo, Cad),
    !.

outros_lugares(ctx(_, Lugares), Eu, Cads) :-
    exclude(lugar_de_algum([Eu]), Lugares, Outros),
    pairs_values(Outros, Cads).

lugar_de_algum(Amigos, Amigo-_) :-
    memberchk(Amigo, Amigos).

%!  amigos_citados(+Mania, -Amigos) is det.
%
%   De quais outros amigos a mania depende. Usado para decidir quando uma
%   mania ainda está "pendente" (seção 5).
amigos_citados(de_frente_para_algum(As), As) :- !.
amigos_citados(perto_de(A), [A]) :- !.
amigos_citados(lado_a_lado_com(A), [A]) :- !.
amigos_citados(longe_de(A), [A]) :- !.
amigos_citados(_, []).


/* =========================================================================
   4. MODELO DA FASE (restrições sobre as posições)
   ========================================================================= */

%!  restricoes(+Mesa, +Amigos, +Sentados, -Lugares) is semidet.
%
%   Lugares = [[Amigo, Linha, Coluna], ...], um para cada amigo da fase, em
%   que Linha e Coluna são variáveis CLP(FD) (ou números, para quem já está
%   em Sentados). Impõe: cadeira dentro da mesa, um amigo por cadeira e
%   todas as manias. Não faz a busca: quem resolve chama label/1 sobre
%   lugares_vars/2. Falha se a propagação já provar que é impossível.
restricoes(Mesa, Amigos, Sentados, Lugares) :-
    restricoes(Mesa, Amigos, Amigos, Sentados, Lugares).

%   Só impõe as manias de ComMania: a dica (seção 8) testa subconjuntos.
restricoes(mesa(Linhas, Colunas, Objetos), Amigos, ComMania, Sentados,
           Lugares) :-
    maplist(lugar_inicial(Linhas, Colunas, Sentados), Amigos, Pares),
    um_por_cadeira(Colunas, Pares),
    ctx(Objetos, Pares, Ctx),
    maplist(impoe_mania(Ctx), ComMania),
    maplist(par_lista, Pares, Lugares).

lugar_inicial(Linhas, Colunas, Sentados, Amigo, Amigo-cad(L, C)) :-
    (   memberchk([Amigo, L0, C0], Sentados)
    ->  L = L0, C = C0
    ;   true
    ),
    UltimaL is Linhas - 1,
    UltimaC is Colunas - 1,
    L in 0..UltimaL,
    C in 0..UltimaC.

%   Cada cadeira vira um número único Linha*Colunas+Coluna, e all_distinct
%   impede dois amigos no mesmo lugar. Fora daqui usamos as coordenadas.
um_por_cadeira(Colunas, Pares) :-
    pairs_values(Pares, Cads),
    maplist(indice_cadeira(Colunas), Cads, Indices),
    all_distinct(Indices).

indice_cadeira(Colunas, cad(L, C), I) :-
    I #= L * Colunas + C.

impoe_mania(Ctx, Amigo) :-
    (   mania(Amigo, Mania)
    ->  mania_vale(Mania, Amigo, Ctx, 1)
    ;   true
    ).

ctx(Objetos, Pares, ctx(ObjPares, Pares)) :-
    maplist(objeto_par, Objetos, ObjPares).

objeto_par([Objeto, L, C], Objeto-cad(L, C)).

par_lista(Amigo-cad(L, C), [Amigo, L, C]).

%!  lugares_vars(+Lugares, -Vars) is det.
%
%   As variáveis de Lugares numa lista só, prontas para label/1.
lugares_vars(Lugares, Vars) :-
    maplist(coordenadas, Lugares, Pares),
    append(Pares, Vars).

coordenadas([_, L, C], [L, C]).


/* =========================================================================
   5. VALIDAR ESTADO E JOGADA
   ========================================================================= */

%!  estado_valido(+Mesa, +Amigos, +Sentados) is semidet.
%
%   O tabuleiro é possível de existir: amigos e objetos conhecidos, objetos
%   dentro da mesa, todo sentado é um amigo da fase,
%   ninguém senta duas vezes, toda cadeira está dentro da mesa e não há
%   duas pessoas na mesma cadeira. Não olha as manias (isso é
%   status_manias/4): um estado com mania ❌ continua sendo um estado.
estado_valido(mesa(Linhas, Colunas, Objetos), Amigos, Sentados) :-
    maplist(amigo, Amigos),
    maplist(objeto_valido(Linhas, Colunas), Objetos),
    is_list(Sentados),
    maplist(sentado_valido(Linhas, Colunas, Amigos), Sentados),
    pairs_de_sentados(Sentados, Nomes, Cads),
    sort(Nomes, NomesUnicos), same_length(Nomes, NomesUnicos),
    sort(Cads, CadsUnicas), same_length(Cads, CadsUnicas).

sentado_valido(Linhas, Colunas, Amigos, [Amigo, L, C]) :-
    memberchk(Amigo, Amigos),
    cadeira_na_mesa(Linhas, Colunas, L, C).

objeto_valido(Linhas, Colunas, [Objeto, L, C]) :-
    objeto(Objeto),
    cadeira_na_mesa(Linhas, Colunas, L, C).

cadeira_na_mesa(Linhas, Colunas, L, C) :-
    integer(L), integer(C),
    L >= 0, L < Linhas,
    C >= 0, C < Colunas.

pairs_de_sentados(Sentados, Nomes, Cads) :-
    findall(A, member([A, _, _], Sentados), Nomes),
    findall(L-C, member([_, L, C], Sentados), Cads).

%!  jogada_valida(+Mesa, +Amigos, +Sentados, +Amigo, +Cadeira) is semidet.
%
%   Cadeira = [Linha, Coluna]. Sentar Amigo ali é permitido pelas regras do
%   tabuleiro: o amigo é da fase e ainda está de pé, e a cadeira existe e
%   está livre. A jogada pode deixar manias ❌; isso é permitido e aparece
%   no status, como no Sudoku do template.
jogada_valida(Mesa, Amigos, Sentados, Amigo, [L, C]) :-
    estado_valido(Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, [[Amigo, L, C] | Sentados]).

%!  status_manias(+Mesa, +Amigos, +Sentados, -Status) is det.
%
%   Status = [[Amigo, S], ...] para cada amigo da fase, com S em
%
%       ok        a mania está respeitada            ✅
%       violada   a mania está desrespeitada         ❌
%       pendente  o amigo, ou alguém que a mania cita, ainda não sentou
%
%   Usa o MESMO interpretador do resolvedor, agora com números no lugar das
%   variáveis: o CLP(FD) só calcula B. Só entram em Ctx os amigos sentados.
status_manias(mesa(_, _, Objetos), Amigos, Sentados, Status) :-
    findall(A-cad(L, C), member([A, L, C], Sentados), Pares),
    ctx(Objetos, Pares, Ctx),
    pairs_keys(Pares, SentadosNomes),
    maplist(status_de(Ctx, Amigos, SentadosNomes), Amigos, Status).

status_de(Ctx, Amigos, SentadosNomes, Amigo, [Amigo, S]) :-
    (   \+ memberchk(Amigo, SentadosNomes)
    ->  S = pendente
    ;   \+ mania(Amigo, _)
    ->  S = ok
    ;   mania(Amigo, Mania),
        amigos_citados(Mania, Citados),
        member(X, Citados), memberchk(X, Amigos),
        \+ memberchk(X, SentadosNomes)
    ->  S = pendente
    ;   mania(Amigo, Mania),
        mania_vale(Mania, Amigo, Ctx, B),
        (   B =:= 1
        ->  S = ok
        ;   S = violada
        )
    ).

%!  venceu(+Mesa, +Amigos, +Sentados) is semidet.
%
%   Todo mundo sentado e todas as manias ✅.
venceu(Mesa, Amigos, Sentados) :-
    estado_valido(Mesa, Amigos, Sentados),
    length(Amigos, N),
    length(Sentados, N),
    status_manias(Mesa, Amigos, Sentados, Status),
    forall(member([_, S], Status), S == ok).


/* =========================================================================
   6. RESOLVEDOR
   ========================================================================= */

%!  solve(+Mesa, +Amigos, +Sentados, -Solucao) is nondet.
%
%   Solucao = [[Amigo, Linha, Coluna], ...] com todos os amigos da fase,
%   mantendo os Sentados no lugar. Falha se não houver solução.
solve(Mesa, Amigos, Sentados, Solucao) :-
    estado_valido(Mesa, Amigos, Sentados),
    restricoes(Mesa, Amigos, Sentados, Solucao),
    lugares_vars(Solucao, Vars),
    labeling([ff], Vars).

%!  count_solutions(+Mesa, +Amigos, +Sentados, +Limite, -N) is det.
count_solutions(Mesa, Amigos, Sentados, Limite, N) :-
    aggregate_all(count, limit(Limite, solve(Mesa, Amigos, Sentados, _)), N).


/* =========================================================================
   7. GERADOR
   ========================================================================= */

%!  generate(+Nivel, -Mesa, -Amigos, -Sentados) is semidet.
%
%   Nivel é facil, medio ou dificil. A fase gerada tem solução única e
%   Sentados são os amigos que já começam na cadeira (as âncoras).
generate(Nivel, Mesa, Amigos, Sentados) :-
    nivel(Nivel, _, _, _, _),
    between(1, 50, _),
    fase_candidata(Nivel, Mesa, Amigos, Sentados),
    !.

%   nivel(Nivel, Linhas, Colunas, NumAmigos, MaxSentados)
nivel(facil,   2, 3, 4, 1).
nivel(medio,   3, 3, 5, 2).
nivel(dificil, 3, 4, 7, 3).

fase_candidata(Nivel, Mesa, Amigos, Sentados) :-
    nivel(Nivel, Linhas, Colunas, NumAmigos, MaxSentados),
    findall(A, amigo(A), Todos),
    random_permutation(Todos, Embaralhados),
    length(Amigos, NumAmigos),
    append(Amigos, _, Embaralhados),
    objetos_aleatorios(Linhas, Colunas, Objetos),
    Mesa = mesa(Linhas, Colunas, Objetos),
    solucao_aleatoria(Mesa, Amigos, Solucao),
    random_permutation(Solucao, Candidatos),
    ancoras(Mesa, Amigos, Candidatos, [], Ancoras),
    enxuga(Mesa, Amigos, Ancoras, Ancoras, Sentados),
    length(Sentados, N),
    N =< MaxSentados.

objetos_aleatorios(Linhas, Colunas, Objetos) :-
    findall([L, C], (between(1, Linhas, L1), L is L1 - 1,
                     between(1, Colunas, C1), C is C1 - 1), Cadeiras),
    random_permutation(Cadeiras, [[LP, CP], [LT, CT], [LD, CD] | _]),
    random_member(Decoracao, [janela, estante]),
    Objetos = [[porta, LP, CP], [tomada, LT, CT], [Decoracao, LD, CD]].

solucao_aleatoria(Mesa, Amigos, Solucao) :-
    restricoes(Mesa, Amigos, [], Solucao),
    lugares_vars(Solucao, Vars),
    once(rotulo_aleatorio(Vars)).

rotulo_aleatorio([]).
rotulo_aleatorio([V | Vs]) :-
    (   integer(V)
    ->  true
    ;   fd_dom(V, Dom),
        findall(X, (X in Dom, indomain(X)), Valores),
        random_permutation(Valores, Ordem),
        member(V, Ordem)
    ),
    rotulo_aleatorio(Vs).

%   Fixa amigos da solução, um por vez, até a solução ficar única.
ancoras(Mesa, Amigos, Candidatos, Ancoras0, Ancoras) :-
    (   count_solutions(Mesa, Amigos, Ancoras0, 2, 1)
    ->  Ancoras = Ancoras0
    ;   Candidatos = [Lugar | Resto],
        ancoras(Mesa, Amigos, Resto, [Lugar | Ancoras0], Ancoras)
    ).

%   Tira as âncoras que não são necessárias para a solução continuar única.
enxuga(_, _, [], Ancoras, Ancoras).
enxuga(Mesa, Amigos, [Lugar | Resto], Ancoras0, Ancoras) :-
    selectchk(Lugar, Ancoras0, Sem),
    (   count_solutions(Mesa, Amigos, Sem, 2, 1)
    ->  enxuga(Mesa, Amigos, Resto, Sem, Ancoras)
    ;   enxuga(Mesa, Amigos, Resto, Ancoras0, Ancoras)
    ).


/* =========================================================================
   8. DICA
   =========================================================================

   Uma cadeira é considerada forçada quando um conjunto de manias já é suficiente para
   deixar apenas uma opção para o amigo. Procuramos o menor conjunto de manias possível
   e usamos uma delas como motivo da dica.
*/

%!  hint(+Mesa, +Amigos, +Sentados, -Dica) is semidet.
%
%   Retorna uma jogada forçada, indica que a mesa está completa
%   ou que não existe solução para o estado atual.
%
%   Falha se o estado for inválido ou se não houver uma jogada forçada.
hint(Mesa, Amigos, Sentados, Dica) :-
    estado_valido(Mesa, Amigos, Sentados),
    (   \+ solve(Mesa, Amigos, Sentados, _)
    ->  Dica = [sem_solucao]
    ;   length(Amigos, N),
        length(Sentados, N)
    ->  Dica = [completo]
    ;   jogada_forcada(Mesa, Amigos, Sentados, Amigo, L, C, Manias),
        motivo(Amigo, Manias, Dono),
        Dica = [sentar, Amigo, L, C, Dono]
    ).

jogada_forcada(Mesa, Amigos, Sentados, Amigo, L, C, Manias) :-
    include(tem_mania, Amigos, ComMania),
    exclude(ja_sentou(Sentados), Amigos, DePe),
    length(ComMania, Max),
    between(0, Max, K),
    combinacao(K, ComMania, Manias),
    partition(pertence(Manias), DePe, Citados, Outros),
    append(Citados, Outros, Candidatos),
    member(Amigo, Candidatos),
    unica_cadeira(Mesa, Amigos, Manias, Sentados, Amigo, L, C),
    !.

unica_cadeira(Mesa, Amigos, Manias, Sentados, Amigo, L, C) :-
    findall(L0-C0,
            limit(2, cadeira_possivel(Mesa, Amigos, Manias, Sentados,
                                      Amigo, L0, C0)),
            [L-C]).

cadeira_possivel(Mesa, Amigos, Manias, Sentados, Amigo, L, C) :-
    Mesa = mesa(Linhas, Colunas, _),
    UltimaL is Linhas - 1,
    UltimaC is Colunas - 1,
    between(0, UltimaL, L),
    between(0, UltimaC, C),
    \+ memberchk([_, L, C], Sentados),
    \+ \+ ( restricoes(Mesa, Amigos, Manias, Sentados, Lugares),
            memberchk([Amigo, L, C], Lugares),
            lugares_vars(Lugares, Vars),
            once(labeling([ff], Vars))
          ).

motivo(Amigo, Manias, Amigo) :-
    (   Manias == []
    ;   memberchk(Amigo, Manias)
    ),
    !.
motivo(_, [Dono | _], Dono).

tem_mania(Amigo) :-
    mania(Amigo, _).

ja_sentou(Sentados, Amigo) :-
    memberchk([Amigo, _, _], Sentados).

pertence(Lista, X) :-
    memberchk(X, Lista).

combinacao(0, _, []).
combinacao(K, [X | Xs], [X | Ys]) :-
    K > 0,
    K1 is K - 1,
    combinacao(K1, Xs, Ys).
combinacao(K, [_ | Xs], Ys) :-
    K > 0,
    combinacao(K, Xs, Ys).


/* =========================================================================
   9. EXEMPLO PARA O TERMINAL
   ========================================================================= */

%!  fase_exemplo(-Mesa, -Amigos, -Sentados) is det.
%
%   Mesa 2x3 com a porta no canto de cima à esquerda e a tomada no canto de
%   cima à direita. O Bevi já começa sentado embaixo, no meio. A única
%   solução é Mayara (0,0), Arthur (0,1) e João (0,2).
fase_exemplo(mesa(2, 3, [[porta, 0, 0], [tomada, 0, 2]]),
             [arthur, joao, mayara, bevi],
             [[bevi, 1, 1]]).
