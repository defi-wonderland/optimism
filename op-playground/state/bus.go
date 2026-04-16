package state

import (
	"encoding/json"
	"sync"
	"time"
)

type Event struct {
	Type string          `json:"type"`
	Time time.Time       `json:"time"`
	Data json.RawMessage `json:"data"`
}

func NewEvent(typ string, data any) Event {
	raw, _ := json.Marshal(data)
	return Event{Type: typ, Time: time.Now(), Data: raw}
}

type Bus struct {
	mu      sync.RWMutex
	subs    map[chan Event]struct{}
	backlog []Event
}

func NewBus() *Bus {
	return &Bus{
		subs:    make(map[chan Event]struct{}),
		backlog: make([]Event, 0, 256),
	}
}

const maxBacklog = 200

func (b *Bus) Publish(e Event) {
	b.mu.Lock()
	b.backlog = append(b.backlog, e)
	if len(b.backlog) > maxBacklog {
		b.backlog = b.backlog[len(b.backlog)-maxBacklog:]
	}
	subs := make([]chan Event, 0, len(b.subs))
	for ch := range b.subs {
		subs = append(subs, ch)
	}
	b.mu.Unlock()

	for _, ch := range subs {
		select {
		case ch <- e:
		default:
		}
	}
}

func (b *Bus) Subscribe() (ch chan Event, unsub func()) {
	ch = make(chan Event, 64)
	b.mu.Lock()
	for _, e := range b.backlog {
		select {
		case ch <- e:
		default:
		}
	}
	b.subs[ch] = struct{}{}
	b.mu.Unlock()
	return ch, func() {
		b.mu.Lock()
		delete(b.subs, ch)
		b.mu.Unlock()
	}
}
