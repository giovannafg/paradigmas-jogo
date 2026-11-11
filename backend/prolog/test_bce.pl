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
