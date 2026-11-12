/*  test_bce.pl: Testes plunit do jogo da BCE.

    Para rodar:
        $ swipl -g run_tests -t halt backend/prolog/test_bce.pl
*/

:- use_module(bce).
:- use_module(library(plunit)).
:- use_module(library(lists)).

:- begin_tests(solve).

test(fase_exemplo, [nondet, true(Solucao == [[arthur, 0, 1], [joao, 0, 2], [mayara, 0, 0], [bevi, 1, 1]])]) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    solve(Mesa, Amigos, Sentados, Solucao).

test(solucao_vence) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    once(solve(Mesa, Amigos, Sentados, Solucao)),
    venceu(Mesa, Amigos, Solucao).

test(mantem_sentados, nondet) :-
    fase_exemplo(Mesa, Amigos, _),
    solve(Mesa, Amigos, [[joao, 0, 2]], Solucao),
    memberchk([joao, 0, 2], Solucao).

test(sem_solucao, fail) :-
    solve(mesa(1, 2, []), [bevi, arthur], [], _).

test(sentados_conflitantes, fail) :-
    fase_exemplo(Mesa, Amigos, _),
    solve(Mesa, Amigos, [[mayara, 0, 1]], _).

test(estado_invalido, fail) :-
    solve(mesa(2, 2, []), [bevi], [[bevi, 5, 5]], _).

test(unica, N == 1) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    count_solutions(Mesa, Amigos, Sentados, 2, N).

test(sem_ancora_varias, N == 7) :-
    fase_exemplo(Mesa, Amigos, _),
    count_solutions(Mesa, Amigos, [], 100, N).

test(respeita_limite, N == 2) :-
    fase_exemplo(Mesa, Amigos, _),
    count_solutions(Mesa, Amigos, [], 2, N).

:- end_tests(solve).

:- begin_tests(generate).

niveis([facil, medio, dificil]).

test(solucao_unica, forall((niveis(Ns), member(N, Ns), between(1, 5, _)))) :-
    generate(N, Mesa, Amigos, Sentados),
    count_solutions(Mesa, Amigos, Sentados, 2, 1).

test(estado_valido, forall((niveis(Ns), member(N, Ns)))) :-
    generate(N, Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, Sentados).

test(sobra_jogo, forall((niveis(Ns), member(N, Ns)))) :-
    generate(N, _, Amigos, Sentados),
    length(Amigos, A),
    length(Sentados, S),
    A - S >= 3.

test(tamanho_por_nivel, [Tamanhos == [2-3-4, 3-3-5, 3-4-7]]) :-
    niveis(Ns),
    findall(L-C-A,
            ( member(N, Ns),
              generate(N, mesa(L, C, _), Amigos, _),
              length(Amigos, A) ),
            Tamanhos).

test(rapido, forall((niveis(Ns), member(N, Ns)))) :-
    statistics(cputime, T0),
    generate(N, _, _, _),
    statistics(cputime, T1),
    T1 - T0 < 2.

test(nivel_desconhecido, fail) :-
    generate(impossivel, _, _, _).

:- end_tests(generate).

:- begin_tests(hint).

test(propria_mania_forca, Dica == [sentar, joao, 0, 2, joao]) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    hint(Mesa, Amigos, Sentados, Dica).

test(mania_do_proprio_amigo, Dica == [sentar, mayara, 0, 0, mayara]) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    hint(Mesa, Amigos, [[joao, 0, 2] | Sentados], Dica).

test(mania_de_outro_amigo, Dica == [sentar, arthur, 0, 1, bevi]) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    hint(Mesa, Amigos, [[mayara, 0, 0], [joao, 0, 2] | Sentados], Dica).

test(ultima_cadeira_livre, Dica == [sentar, joao, 0, 1, joao]) :-
    hint(mesa(1, 2, []), [arthur, joao], [[arthur, 0, 0]], Dica).

test(completo, Dica == [completo]) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    once(solve(Mesa, Amigos, Sentados, Solucao)),
    hint(Mesa, Amigos, Solucao, Dica).

test(sem_solucao, Dica == [sem_solucao]) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    hint(Mesa, Amigos, [[mayara, 0, 1] | Sentados], Dica).

test(completo_errado, Dica == [sem_solucao]) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    hint(Mesa, Amigos,
         [[arthur, 0, 0], [joao, 0, 2], [mayara, 0, 1] | Sentados], Dica).

test(nada_forcado, fail) :-
    hint(mesa(1, 2, []), [arthur, joao], [], _).

test(estado_invalido, fail) :-
    fase_exemplo(Mesa, Amigos, _),
    hint(Mesa, Amigos, [[bevi, 9, 9]], _).

test(dicas_resolvem_fase, forall(member(N, [facil, medio, dificil]))) :-
    generate(N, Mesa, Amigos, Sentados),
    once(solve(Mesa, Amigos, Sentados, Solucao)),
    segue_dicas(Mesa, Amigos, Sentados, Solucao).

segue_dicas(Mesa, Amigos, Sentados, Solucao) :-
    hint(Mesa, Amigos, Sentados, Dica),
    (   Dica == [completo]
    ->  true
    ;   Dica = [sentar, Amigo, L, C, Dono],
        mania(Dono, _),
        memberchk([Amigo, L, C], Solucao),
        segue_dicas(Mesa, Amigos, [[Amigo, L, C] | Sentados], Solucao)
    ).

:- end_tests(hint).
