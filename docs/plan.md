# Plan (Day-by-day)

## Locked assumptions / rationale

### Why h/R sweep starts from 4 (reference)
NASA outwash ground-effect 연구에서 ground effect는 rotor disk가 지면에서 "a few rotor radii" 이내일 때 중요하다고 설명한다.
따라서 h/R=4를 사실상 OGE-like reference로 사용한다.

### Why exclude h/R=0.25
Cheeseman–Bennett(1955) hover ground effect 이론식(상수 동력)에서
Tg/T∞ = 1/(1 - R^2/(16 Z^2)).
Z/R=0.25에서 분모가 0이 되어 특이점이 발생하므로 제외한다. 최저치는 0.35로 설정한다.

### What we compare to literature
- Cheeseman–Bennett(1955): "at constant power" 조건의 thrust ratio 식과 비교(상수동력 케이스는 n 조정으로 별도 수행)
- NASA outwash: peak velocity가 r/R ≈ 1.7~1.8에서 발생, low rotor height에서 peak가 z≈0.02R 근방에 집중된다는 관찰과 비교
