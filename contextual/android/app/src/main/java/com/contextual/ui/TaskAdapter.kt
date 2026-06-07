package com.contextual.ui

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.contextual.data.Task
import com.contextual.data.TaskStatus
import com.contextual.databinding.ItemTaskBinding

class TaskAdapter(
    private val onComplete: (Task) -> Unit,
    private val onClick: (Task) -> Unit
) : ListAdapter<Task, TaskAdapter.TaskViewHolder>(TaskDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): TaskViewHolder {
        val binding = ItemTaskBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return TaskViewHolder(binding)
    }

    override fun onBindViewHolder(holder: TaskViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class TaskViewHolder(
        private val binding: ItemTaskBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(task: Task) {
            binding.taskTitle.text = task.title
            binding.taskNotes.apply {
                text = task.notes
                visibility = if (task.notes.isNullOrEmpty()) View.GONE else View.VISIBLE
            }

            binding.completeButton.setImageResource(
                if (task.status == TaskStatus.COMPLETED) android.R.drawable.checkbox_on_background
                else android.R.drawable.checkbox_off_background
            )
            binding.completeButton.setOnClickListener { onComplete(task) }
            binding.root.setOnClickListener { onClick(task) }

            binding.root.alpha = if (task.status == TaskStatus.COMPLETED) 0.6f else 1.0f
        }
    }
}

class TaskDiffCallback : DiffUtil.ItemCallback<Task>() {
    override fun areItemsTheSame(oldItem: Task, newItem: Task): Boolean = oldItem.id == newItem.id
    override fun areContentsTheSame(oldItem: Task, newItem: Task): Boolean = oldItem == newItem
}
