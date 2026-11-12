/*  test_bce.pl: Testes plunit do jogo da BCE.

    Para rodar:
        $ swipl -g run_tests -t halt backend/prolog/test_bce.pl
*/

:- use_module(bce).
:- use_module(library(plunit)).
:- use_module(library(lists)).

:- begin_tests(estado_valido).

test(fase_exemplo) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, Sentados).

test(ninguem_sentado) :-
    fase_exemplo(Mesa, Amigos, _),
    estado_valido(Mesa, Amigos, []).

test(amigo_desconhecido, fail) :-
    estado_valido(mesa(2, 3, []), [fulano], []).

test(amigo_repetido, fail) :-
    estado_valido(mesa(2, 3, []), [arthur, arthur], []).

test(objeto_desconhecido, fail) :-
    estado_valido(mesa(2, 3, [[sofa, 0, 0]]), [arthur], []).

test(objeto_fora_da_mesa, fail) :-
    estado_valido(mesa(2, 3, [[porta, 2, 0]]), [arthur], []).

test(sentado_fora_da_fase, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, [[felipe, 0, 0] | Sentados]).

test(sentado_duas_vezes, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, [[bevi, 0, 0] | Sentados]).

test(mesma_cadeira, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, [[joao, 1, 1] | Sentados]).

test(cadeira_fora_da_mesa, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, [[joao, 0, 3] | Sentados]).

test(cadeira_negativa, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, [[joao, -1, 0] | Sentados]).

test(sentados_nao_lista, fail) :-
    fase_exemplo(Mesa, Amigos, _),
    estado_valido(Mesa, Amigos, joao).

test(lugar_incompleto, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, [[joao, 0] | Sentados]).

test(coordenada_nao_numero, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    estado_valido(Mesa, Amigos, [[joao, a, 0] | Sentados]).

test(dimensao_nao_numero, fail) :-
    estado_valido(mesa(dois, 3, [[porta, 0, 0]]), [arthur], []).

test(mesa_sem_cadeiras, fail) :-
    estado_valido(mesa(0, 3, []), [arthur], []).

test(mesa_negativa, fail) :-
    estado_valido(mesa(-1, 3, []), [arthur], []).

test(mesa_grande_demais, fail) :-
    estado_valido(mesa(1000000, 1000000, []), [arthur], []).

test(mesa_no_limite) :-
    estado_valido(mesa(6, 6, []), [arthur], []).

:- end_tests(estado_valido).

:- begin_tests(jogada_valida).

test(cadeira_livre) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    jogada_valida(Mesa, Amigos, Sentados, joao, [0, 2]).

test(pode_violar_mania) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    jogada_valida(Mesa, Amigos, Sentados, mayara, [1, 0]).

test(cadeira_ocupada, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    jogada_valida(Mesa, Amigos, Sentados, joao, [1, 1]).

test(amigo_ja_sentado, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    jogada_valida(Mesa, Amigos, Sentados, bevi, [0, 0]).

test(amigo_fora_da_fase, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    jogada_valida(Mesa, Amigos, Sentados, felipe, [0, 0]).

test(fora_da_mesa, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    jogada_valida(Mesa, Amigos, Sentados, joao, [2, 0]).

test(estado_invalido, fail) :-
    fase_exemplo(Mesa, Amigos, _),
    jogada_valida(Mesa, Amigos, [[bevi, 9, 9]], joao, [0, 2]).

:- end_tests(jogada_valida).

:- begin_tests(status_manias).

status(Mesa, Amigos, Sentados, Amigo, S) :-
    status_manias(Mesa, Amigos, Sentados, Status),
    memberchk([Amigo, S], Status).

caso(perto_de_objeto,
     mesa(2, 3, [[porta, 0, 0]]), [arthur], [[arthur, 1, 1]],
     arthur, ok).
caso(perto_de_objeto_na_cadeira,
     mesa(2, 3, [[porta, 0, 0]]), [arthur], [[arthur, 0, 0]],
     arthur, ok).
caso(perto_de_objeto_longe,
     mesa(2, 3, [[porta, 0, 0]]), [arthur], [[arthur, 0, 2]],
     arthur, violada).

caso(na_cadeira_de,
     mesa(2, 3, [[tomada, 0, 2]]), [joao], [[joao, 0, 2]],
     joao, ok).
caso(na_cadeira_de_ao_lado,
     mesa(2, 3, [[tomada, 0, 2]]), [joao], [[joao, 0, 1]],
     joao, violada).

caso(sem_vizinhos,
     mesa(2, 3, []), [bevi, joao], [[bevi, 1, 1], [joao, 0, 1]],
     bevi, ok).
caso(sem_vizinhos_lado_a_lado,
     mesa(2, 3, []), [bevi, joao], [[bevi, 1, 1], [joao, 1, 2]],
     bevi, violada).

caso(de_frente_para_algum,
     mesa(2, 3, []), [felipe, arthur], [[felipe, 1, 0], [arthur, 0, 0]],
     felipe, ok).
caso(de_frente_para_algum_diagonal,
     mesa(2, 3, []), [felipe, arthur], [[felipe, 1, 0], [arthur, 0, 1]],
     felipe, violada).

caso(perto_de,
     mesa(2, 3, []), [gabriel, arthur], [[gabriel, 0, 0], [arthur, 1, 1]],
     gabriel, ok).
caso(perto_de_longe,
     mesa(2, 3, []), [gabriel, arthur], [[gabriel, 0, 0], [arthur, 1, 2]],
     gabriel, violada).

caso(lado_a_lado_com,
     mesa(2, 3, []), [giovanna, mayara], [[giovanna, 0, 0], [mayara, 0, 1]],
     giovanna, ok).
caso(lado_a_lado_com_de_frente,
     mesa(2, 3, []), [giovanna, mayara], [[giovanna, 0, 0], [mayara, 1, 0]],
     giovanna, violada).

caso(longe_de,
     mesa(2, 3, []), [mayara, joao], [[mayara, 0, 0], [joao, 0, 2]],
     mayara, ok).
caso(longe_de_perto,
     mesa(2, 3, []), [mayara, joao], [[mayara, 0, 0], [joao, 1, 1]],
     mayara, violada).

caso(amigo_de_pe,
     mesa(2, 3, []), [mayara, joao], [[joao, 0, 2]],
     mayara, pendente).
caso(citado_de_pe,
     mesa(2, 3, []), [mayara, joao], [[mayara, 0, 0]],
     mayara, pendente).
caso(citado_fora_da_fase,
     mesa(2, 3, []), [gabriel], [[gabriel, 0, 0]],
     gabriel, ok).
caso(objeto_fora_da_mesa,
     mesa(2, 3, []), [joao], [[joao, 0, 0]],
     joao, ok).

test(caso, [forall(caso(_Nome, Mesa, Amigos, Sentados, Amigo, Esperado)),
            true(S == Esperado)]) :-
    status(Mesa, Amigos, Sentados, Amigo, S).

test(ninguem_sentado, Status == [[arthur, pendente], [joao, pendente],
                                 [mayara, pendente], [bevi, pendente]]) :-
    fase_exemplo(Mesa, Amigos, _),
    status_manias(Mesa, Amigos, [], Status).

:- end_tests(status_manias).

:- begin_tests(venceu).

test(incompleto, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    venceu(Mesa, Amigos, Sentados).

test(completo_com_mania_violada, fail) :-
    fase_exemplo(Mesa, Amigos, Sentados),
    venceu(Mesa, Amigos,
           [[arthur, 0, 0], [joao, 0, 2], [mayara, 0, 1] | Sentados]).

:- end_tests(venceu).

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

test(ultima_cadeira_livre, Dica == [sentar, joao, 0, 1, nenhuma]) :-
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
        (   Dono == nenhuma
        ->  true
        ;   mania(Dono, _)
        ),
        memberchk([Amigo, L, C], Solucao),
        segue_dicas(Mesa, Amigos, [[Amigo, L, C] | Sentados], Solucao)
    ).

:- end_tests(hint).
