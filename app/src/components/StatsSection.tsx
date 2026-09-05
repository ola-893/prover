import { useEffect, useRef, useState } from 'react';
import { motion, useInView } from 'motion/react';

function AnimatedNumber({ value, suffix = '', prefix = '' }: { value: number; suffix?: string; prefix?: string }) {
  const [count, setCount] = useState(0);
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, margin: '-100px' });

  useEffect(() => {
    if (!inView) return;
    const duration = 2000;
    const steps = 60;
    const increment = value / steps;
    let current = 0;
    const timer = setInterval(() => {
      current += increment;
      if (current >= value) {
        setCount(value);
        clearInterval(timer);
      } else {
        setCount(Math.floor(current));
      }
    }, duration / steps);
    return () => clearInterval(timer);
  }, [inView, value]);

  return (
    <span ref={ref}>
      {prefix}{count.toLocaleString()}{suffix}
    </span>
  );
}

export default function StatsSection() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: '-100px' });

  const stats = [
    { value: 5, label: 'Supported proof routes', suffix: '' },
    { value: 3, label: 'Live evidence roles', suffix: '' },
    { value: 0, label: 'Human verdicts', suffix: '' },
    { value: 1, label: 'Soulbound card standard', suffix: '' },
  ];

  return (
    <section ref={ref} className="bg-white py-24 sm:py-32 border-b border-[#111111]">
      <div className="max-w-7xl mx-auto px-6 sm:px-10 lg:px-16">
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-8 lg:gap-0 lg:divide-x lg:divide-[#111111]">
          {stats.map((stat, i) => (
            <motion.div
              key={stat.label}
              initial={{ opacity: 0, y: 30 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.5, delay: i * 0.1 }}
              className="text-center px-4 sm:px-8 py-6"
            >
              <div className="font-serif text-5xl sm:text-6xl lg:text-7xl text-[#111111] font-normal tracking-tight leading-none mb-3">
                <AnimatedNumber value={stat.value} suffix={stat.suffix} />
              </div>
              <div className="font-mono text-[10px] sm:text-xs text-[#888888] uppercase tracking-widest">
                {stat.label}
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
