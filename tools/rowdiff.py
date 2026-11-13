"""Counts the pixel rows that differ between two PPM captures of the panel.

Used by tools/repro-open.sh: more than 100 changed rows means the panel was
still filling in when the first capture was taken. Exits 1 in that case.
"""
import sys

LIMIT = 100


def load(path):
    data = open(path, "rb").read()
    tokens, i = [], 0
    while len(tokens) < 4:
        while data[i:i + 1].isspace():
            i += 1
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        tokens.append(data[i:j])
        i = j
    return int(tokens[1]), int(tokens[2]), data[i + 1:]


def changed_rows(a, b, width, height):
    # Every third channel of every third pixel is enough to see a section appear.
    return sum(
        1 for y in range(height)
        if sum(abs(a[k] - b[k]) for k in range(y * width * 3, (y + 1) * width * 3, 9)) > width * 4
    )


def main():
    width, height, early = load(sys.argv[1])
    _, _, late = load(sys.argv[2])
    rows = changed_rows(early, late, width, height)
    red = rows > LIMIT
    print("rows that change between early and late: %d -> %s"
          % (rows, "RED (panel was incomplete when it opened)" if red else "GREEN"))
    sys.exit(1 if red else 0)


if __name__ == "__main__":
    main()
